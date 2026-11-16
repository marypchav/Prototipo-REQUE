/*
Instala los 19 procedimientos del módulo Gestión de pedidos (GP001 a GP020).
Las tablas ya existen (00_CrearTablas.sql las crea para los tres módulos).
Ejecutar completo en SSMS (F5). Se puede ejecutar varias veces: usa CREATE OR ALTER.
El usuario capanni_app ya puede ejecutarlos (GRANT EXECUTE en toda la base).
*/
USE BDCapanni;
GO

-- ============================================================================
-- spRegistrarCliente
-- ============================================================================
CREATE OR ALTER PROCEDURE dbo.spRegistrarCliente
    @inNombre NVARCHAR(100) -- nombre completo
    , @inCorreo NVARCHAR(200) -- correo (se valida formato y largo máximo de 128)
    , @inTelefono NVARCHAR(30) -- teléfono; se le quitan espacios y guiones
    , @inPassHash VARCHAR(100) -- hash bcrypt que calcula el backend
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP001 Registrar cliente. El perfil se crea con rol de cliente
(EsAdministrador = 0, postcondición 1).
GP001 restricción 3: el largo mínimo de 8 caracteres lo valida el backend
ANTES de calcular el hash (aquí ya solo llega el hash, código 50043).

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spRegistrarCliente
        @inNombre = N'Ana Mora Solís'
        , @inCorreo = N'ana@correo.com'
        , @inTelefono = N'8888-1234'
        , @inPassHash = '$2b$10$abcdefghijklmnopqrstuuJr7v3v4Yp0bW3E3l1E2f1nZ1q0m2e4a'
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0
            , @largoMaxCorreo INT = 128
            , @largoMinTelefono INT = 8
            , @largoMaxTelefono INT = 16;

        -- variables de uso general
        DECLARE @nombre NVARCHAR(100)
            , @correo NVARCHAR(200)
            , @telefono NVARCHAR(30)
            , @passHash VARCHAR(100)
            , @idUsuario INT;

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @nombre = NULLIF(LTRIM(RTRIM(@inNombre)), N'');
        SET @correo = LOWER(NULLIF(LTRIM(RTRIM(@inCorreo)), N''));
        SET @telefono = NULLIF(REPLACE(REPLACE(LTRIM(RTRIM(@inTelefono)), N' ', N''), N'-', N''), N'');
        SET @passHash = NULLIF(LTRIM(RTRIM(@inPassHash)), '');

        -- validaciones
        -- GP001 restricción 1: no se pueden dejar campos vacíos
        IF (@nombre IS NULL)
            OR (@correo IS NULL)
            OR (@telefono IS NULL)
            OR (@passHash IS NULL)
        BEGIN
            SET @outResultCode = 50021; -- campos obligatorios vacíos
            RETURN;
        END;

        -- GP001 restricción 2: formato de correo (texto@texto.texto, una sola @, sin espacios)
        IF (@correo NOT LIKE N'%_@_%._%')
            OR (@correo LIKE N'%[ ,;:<>()]%')
            OR ((LEN(@correo) - LEN(REPLACE(@correo, N'@', N''))) <> 1)
            OR (LEN(@correo) > @largoMaxCorreo)
        BEGIN
            SET @outResultCode = 50040; -- correo con formato inválido
            RETURN;
        END;

        -- teléfono: solo dígitos (con + opcional al inicio), de 8 a 16
        IF (REPLACE(@telefono, N'+', N'') LIKE N'%[^0-9]%')
            OR (CHARINDEX(N'+', @telefono) > 1)
            OR (LEN(@telefono) NOT BETWEEN @largoMinTelefono AND @largoMaxTelefono)
        BEGIN
            SET @outResultCode = 50042; -- teléfono inválido
            RETURN;
        END;

        -- GP001 restricción 2 y flujo alterno 4: correo único
        IF EXISTS (
            SELECT 1
            FROM dbo.Usuario AS U
            WHERE (U.Correo = @correo)
        )
        BEGIN
            SET @outResultCode = 50041; -- correo ya registrado
            RETURN;
        END;

        INSERT INTO dbo.Usuario (
            Nombre
            , Correo
            , Telefono
            , PassHash
            , EsAdministrador
            , FlagActivo
            , FechaCreacion
        )
        VALUES (
            @nombre
            , @correo
            , @telefono
            , @passHash
            , @false -- rol de cliente final
            , @true
            , GETDATE()
        );

        SET @idUsuario = SCOPE_IDENTITY();

        -- primer resultado: el usuario creado
        SELECT @idUsuario AS IdUsuario;

    END TRY
    BEGIN CATCH

        -- dos registros al mismo tiempo con el mismo correo: lo detiene
        -- UQ_Usuario_Correo. No es un error del sistema, es el flujo alterno 4
        IF (ERROR_NUMBER() IN (2601, 2627))
        BEGIN
            SET @outResultCode = 50041; -- correo ya registrado
        END
        ELSE
        BEGIN
            -- registra el error en la tabla de errores
            INSERT INTO dbo.dbError (
                UserName
                , ErrorNumber
                , ErrorState
                , ErrorSeverity
                , ErrorLine
                , ErrorProcedure
                , ErrorMessage
                , ErrorDateTime
            )
            VALUES (
                SUSER_SNAME()
                , ERROR_NUMBER()
                , ERROR_STATE()
                , ERROR_SEVERITY()
                , ERROR_LINE()
                , ERROR_PROCEDURE()
                , ERROR_MESSAGE()
                , GETDATE()
            );

            SET @outResultCode = 50000; -- error inesperado
        END;

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-- ============================================================================
-- spObtenerCredencialCliente
-- ============================================================================
CREATE OR ALTER PROCEDURE dbo.spObtenerCredencialCliente
    @inCorreo NVARCHAR(200) -- correo con el que inicia sesión el cliente
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP002 Iniciar sesión del cliente. Igual que spObtenerCredencialAdmin:
devuelve el hash para que el backend lo compare con bcrypt. Si no coincide,
el backend responde el mismo 50020, sin decir cuál dato falló (flujo alterno).
GP002 restricción 3: solo busca cuentas de cliente (EsAdministrador = 0),
así una sesión de cliente nunca tiene permisos de administración.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spObtenerCredencialCliente
        @inCorreo = N'ana@correo.com'
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0;

        -- variables de uso general
        DECLARE @correo NVARCHAR(200);

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @correo = LOWER(NULLIF(LTRIM(RTRIM(@inCorreo)), N''));

        -- validaciones
        IF (@correo IS NULL)
        BEGIN
            SET @outResultCode = 50021; -- campos obligatorios vacíos
            RETURN;
        END;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Usuario AS U
            WHERE (U.Correo = @correo)
                AND (U.EsAdministrador = @false)
                AND (U.FlagActivo = @true)
        )
        BEGIN
            SET @outResultCode = 50020; -- correo o contraseña incorrectos
            RETURN;
        END;

        -- primer resultado: datos para crear la sesión (el hash no va al navegador)
        SELECT U.IdUsuario
            , U.Nombre
            , U.Correo
            , U.PassHash
        FROM dbo.Usuario AS U
        WHERE (U.Correo = @correo)
            AND (U.EsAdministrador = @false)
            AND (U.FlagActivo = @true);

    END TRY
    BEGIN CATCH

        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION; -- deshace lo que quedó a medias
        END;

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-- ============================================================================
-- spListarDirecciones
-- ============================================================================
CREATE OR ALTER PROCEDURE dbo.spListarDirecciones
    @inIdUsuario INT -- cliente con sesión iniciada
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP003 Visualizar dirección de envío. Solo devuelve las direcciones del
cliente que pide (restricción 1). También sirve para llenar el formulario
de GP005 con los datos actuales.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spListarDirecciones
        @inIdUsuario = 2
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1;

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito

        -- primer resultado: direcciones activas del cliente (vacío = flujo alterno
        -- "Aún no tiene direcciones registradas")
        SELECT D.IdDireccion
            , D.IdProvincia
            , PR.Nombre AS Provincia
            , D.Canton
            , D.Distrito
            , D.OtrasSenas
        FROM dbo.Direccion AS D
        INNER JOIN dbo.Provincia AS PR
            ON (PR.IdProvincia = D.IdProvincia)
        WHERE (D.IdUsuario = @inIdUsuario)
            AND (D.FlagActivo = @true)
        ORDER BY D.FechaCreacion DESC
            , D.IdDireccion DESC;

        -- segundo resultado: provincias para el formulario de GP004 y GP005
        SELECT PR.IdProvincia
            , PR.Nombre
        FROM dbo.Provincia AS PR
        ORDER BY PR.IdProvincia;

    END TRY
    BEGIN CATCH

        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION; -- deshace lo que quedó a medias
        END;

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-- ============================================================================
-- spAgregarDireccion
-- ============================================================================
CREATE OR ALTER PROCEDURE dbo.spAgregarDireccion
    @inIdUsuario INT -- cliente con sesión iniciada
    , @inIdProvincia INT -- provincia
    , @inCanton NVARCHAR(64) -- cantón
    , @inDistrito NVARCHAR(64) -- distrito
    , @inOtrasSenas NVARCHAR(256) -- otras señas
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP004 Agregar dirección de envío. Un cliente puede tener varias (restricción 2).

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spAgregarDireccion
        @inIdUsuario = 2
        , @inIdProvincia = 1
        , @inCanton = N'Desamparados'
        , @inDistrito = N'San Miguel'
        , @inOtrasSenas = N'Higuito, 200 m sur de la iglesia, casa verde'
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1;

        -- variables de uso general
        DECLARE @canton NVARCHAR(64)
            , @distrito NVARCHAR(64)
            , @otrasSenas NVARCHAR(256)
            , @idDireccion INT;

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @canton = NULLIF(LTRIM(RTRIM(@inCanton)), N'');
        SET @distrito = NULLIF(LTRIM(RTRIM(@inDistrito)), N'');
        SET @otrasSenas = NULLIF(LTRIM(RTRIM(@inOtrasSenas)), N'');

        -- validaciones
        -- GP004 restricción 1: provincia, cantón, distrito y otras señas son obligatorios
        IF (@inIdProvincia IS NULL)
            OR (@canton IS NULL)
            OR (@distrito IS NULL)
            OR (@otrasSenas IS NULL)
        BEGIN
            SET @outResultCode = 50021; -- campos obligatorios vacíos
            RETURN;
        END;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Provincia AS PR
            WHERE (PR.IdProvincia = @inIdProvincia)
        )
        BEGIN
            SET @outResultCode = 50045; -- la provincia no existe
            RETURN;
        END;

        INSERT INTO dbo.Direccion (
            IdUsuario
            , IdProvincia
            , Canton
            , Distrito
            , OtrasSenas
            , FlagActivo
            , FechaCreacion
        )
        VALUES (
            @inIdUsuario
            , @inIdProvincia
            , @canton
            , @distrito
            , @otrasSenas
            , @true
            , GETDATE()
        );

        SET @idDireccion = SCOPE_IDENTITY();

        -- primer resultado: la dirección creada (GP012 flujo alterno: al guardarla
        -- se regresa a la selección con esta dirección)
        SELECT @idDireccion AS IdDireccion;

    END TRY
    BEGIN CATCH

        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION; -- deshace lo que quedó a medias
        END;

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-- ============================================================================
-- spModificarDireccion
-- ============================================================================
CREATE OR ALTER PROCEDURE dbo.spModificarDireccion
    @inIdUsuario INT -- cliente con sesión iniciada
    , @inIdDireccion INT -- dirección que se modifica
    , @inIdProvincia INT -- provincia
    , @inCanton NVARCHAR(64) -- cantón
    , @inDistrito NVARCHAR(64) -- distrito
    , @inOtrasSenas NVARCHAR(256) -- otras señas
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP005 Modificar dirección de envío. Mismas validaciones que GP004
(restricción 1). Solo el dueño la puede modificar (restricción 2): si la
dirección es de otro cliente se responde "no existe", sin revelar nada.
Restricción 3: los pedidos guardan una copia en texto de la dirección
(Pedido.DireccionEntrega), así que este cambio no los afecta.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spModificarDireccion
        @inIdUsuario = 2
        , @inIdDireccion = 1
        , @inIdProvincia = 1
        , @inCanton = N'Desamparados'
        , @inDistrito = N'San Miguel'
        , @inOtrasSenas = N'Higuito, 300 m sur de la iglesia, portón negro'
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1;

        -- variables de uso general
        DECLARE @canton NVARCHAR(64)
            , @distrito NVARCHAR(64)
            , @otrasSenas NVARCHAR(256);

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @canton = NULLIF(LTRIM(RTRIM(@inCanton)), N'');
        SET @distrito = NULLIF(LTRIM(RTRIM(@inDistrito)), N'');
        SET @otrasSenas = NULLIF(LTRIM(RTRIM(@inOtrasSenas)), N'');

        -- validaciones
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Direccion AS D
            WHERE (D.IdDireccion = @inIdDireccion)
                AND (D.IdUsuario = @inIdUsuario)
                AND (D.FlagActivo = @true)
        )
        BEGIN
            SET @outResultCode = 50044; -- la dirección no existe
            RETURN;
        END;

        IF (@inIdProvincia IS NULL)
            OR (@canton IS NULL)
            OR (@distrito IS NULL)
            OR (@otrasSenas IS NULL)
        BEGIN
            SET @outResultCode = 50021; -- campos obligatorios vacíos
            RETURN;
        END;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Provincia AS PR
            WHERE (PR.IdProvincia = @inIdProvincia)
        )
        BEGIN
            SET @outResultCode = 50045; -- la provincia no existe
            RETURN;
        END;

        UPDATE dbo.Direccion
        SET IdProvincia = @inIdProvincia
            , Canton = @canton
            , Distrito = @distrito
            , OtrasSenas = @otrasSenas
        WHERE (IdDireccion = @inIdDireccion)
            AND (IdUsuario = @inIdUsuario);

    END TRY
    BEGIN CATCH

        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION; -- deshace lo que quedó a medias
        END;

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-- ============================================================================
-- spEliminarDireccion
-- ============================================================================
CREATE OR ALTER PROCEDURE dbo.spEliminarDireccion
    @inIdUsuario INT -- cliente con sesión iniciada
    , @inIdDireccion INT -- dirección que se elimina
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP006 Eliminar dirección de envío. La confirmación "¿Confirma que desea
eliminar esta dirección?" (restricción 1) la pide el frontend.
Borrado lógico (FlagActivo = 0): deja de mostrarse y de ofrecerse en GP012
(criterio 2). Los pedidos no se afectan porque guardan la dirección en texto.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spEliminarDireccion
        @inIdUsuario = 2
        , @inIdDireccion = 1
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0;

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito

        -- validaciones: debe existir y ser del cliente (GP006 precondición 2)
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Direccion AS D
            WHERE (D.IdDireccion = @inIdDireccion)
                AND (D.IdUsuario = @inIdUsuario)
                AND (D.FlagActivo = @true)
        )
        BEGIN
            SET @outResultCode = 50044; -- la dirección no existe
            RETURN;
        END;

        UPDATE dbo.Direccion
        SET FlagActivo = @false
        WHERE (IdDireccion = @inIdDireccion)
            AND (IdUsuario = @inIdUsuario);

    END TRY
    BEGIN CATCH

        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION; -- deshace lo que quedó a medias
        END;

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-- ============================================================================
-- spAgregarAlCarrito
-- ============================================================================
CREATE OR ALTER PROCEDURE dbo.spAgregarAlCarrito
    @inIdUsuario INT -- cliente con sesión iniciada
    , @inIdProductoTalla INT -- producto + talla elegida en el detalle
    , @inCantidad INT -- cantidad a agregar
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP007 Agregar productos al carrito. No reserva ni toca el inventario
(restricción 3, postcondición 2): las existencias se garantizan en GP014.
Si el producto y la talla ya estaban en el carrito, suma la cantidad sin
superar las existencias (flujo alterno 2). Si las supera, no agrega nada y
devuelve cuántas hay y cuántas tiene ya en el carrito, para el mensaje.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spAgregarAlCarrito
        @inIdUsuario = 2
        , @inIdProductoTalla = 5
        , @inCantidad = 1
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @sinExistencias INT = 0;

        -- variables de uso general
        DECLARE @existencias INT
            , @enCarrito INT;

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito

        -- validaciones
        -- GP007 restricción 2: entero positivo (el backend manda NULL si no es entero)
        IF (@inCantidad IS NULL)
            OR (@inCantidad <= 0)
        BEGIN
            SET @outResultCode = 50046; -- cantidad inválida
            RETURN;
        END;

        SELECT @existencias = PT.Cantidad
        FROM dbo.ProductoTalla AS PT
        INNER JOIN dbo.Producto AS P
            ON (P.IdProducto = PT.IdProducto)
        WHERE (PT.IdProductoTalla = @inIdProductoTalla)
            AND (P.FlagActivo = @true);

        IF (@existencias IS NULL)
        BEGIN
            SET @outResultCode = 50011; -- producto no existe o fue eliminado
            RETURN;
        END;

        -- GP007 restricción 1 y flujo alterno 2: talla agotada
        IF (@existencias <= @sinExistencias)
        BEGIN
            SET @outResultCode = 50047; -- talla agotada
            RETURN;
        END;

        BEGIN TRANSACTION tAgregarAlCarrito;

            -- bloquea la línea del carrito: dos clics seguidos no la duplican
            SELECT @enCarrito = CD.Cantidad
            FROM dbo.CarritoDetalle AS CD WITH (UPDLOCK, HOLDLOCK)
            WHERE (CD.IdUsuario = @inIdUsuario)
                AND (CD.IdProductoTalla = @inIdProductoTalla);

            SET @enCarrito = ISNULL(@enCarrito, 0);

            -- GP007 restricción 2: lo del carrito + lo nuevo no supera las existencias
            IF ((@enCarrito + @inCantidad) > @existencias)
            BEGIN
                ROLLBACK TRANSACTION;
                SET @outResultCode = 50048; -- supera las existencias

                -- datos para el mensaje: "Solo hay N disponibles y ya tiene M en el carrito"
                SELECT @existencias AS Existencias
                    , @enCarrito AS EnCarrito;
                RETURN;
            END;

            IF (@enCarrito > 0)
            BEGIN
                UPDATE dbo.CarritoDetalle
                SET Cantidad = Cantidad + @inCantidad
                    , FechaAgregado = GETDATE()
                WHERE (IdUsuario = @inIdUsuario)
                    AND (IdProductoTalla = @inIdProductoTalla);
            END
            ELSE
            BEGIN
                INSERT INTO dbo.CarritoDetalle (
                    IdUsuario
                    , IdProductoTalla
                    , Cantidad
                    , FechaAgregado
                )
                VALUES (
                    @inIdUsuario
                    , @inIdProductoTalla
                    , @inCantidad
                    , GETDATE()
                );
            END;

        COMMIT TRANSACTION tAgregarAlCarrito;

        -- primer resultado: indicador de productos del carrito (GP007 paso 2.3)
        SELECT ISNULL(SUM(CD.Cantidad), 0) AS CantidadArticulos
        FROM dbo.CarritoDetalle AS CD
        WHERE (CD.IdUsuario = @inIdUsuario);

    END TRY
    BEGIN CATCH

        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION; -- deshace lo que quedó a medias
        END;

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-- ============================================================================
-- spListarCarrito
-- ============================================================================
CREATE OR ALTER PROCEDURE dbo.spListarCarrito
    @inIdUsuario INT -- cliente con sesión iniciada
    , @inIdMetodoEntrega INT -- método de entrega elegido (NULL = aún no elige)
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP008 Visualizar carrito y GP020 Calcular costo del pedido.
Se llama al ver el carrito, después de cada cambio (GP009) y al elegir el
método de entrega (GP012 paso 6.2), así el total siempre está al día
(GP020 restricción 3). Usa el precio vigente del producto (GP020 paso 2.1).

Un producto "No disponible" (eliminado, agotado o con menos existencias que
la cantidad del carrito) se marca y NO entra en el total (GP008 flujo alterno 2,
GP020 flujo alterno 2).
Si el método tiene envío y CostoEnvio es NULL, el total es solo de productos y
EnvioACoordinar = 1: "Envío a coordinar con la administradora" (GP020).

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spListarCarrito
        @inIdUsuario = 2
        , @inIdMetodoEntrega = 4
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0
            , @sinExistencias INT = 0;

        -- variables de uso general
        DECLARE @costoEnvio MONEY
            , @requiereDireccion BIT
            , @envioACoordinar BIT
            , @subtotalProductos MONEY;

        -- líneas del carrito con su disponibilidad actual
        DECLARE @lineas TABLE (
            IdCarritoDetalle INT NOT NULL PRIMARY KEY
            , IdProductoTalla INT NOT NULL
            , IdProducto INT NOT NULL
            , Nombre NVARCHAR(100) NOT NULL
            , RutaImagen VARCHAR(260) NULL
            , Talla NVARCHAR(16) NOT NULL
            , Cantidad INT NOT NULL
            , PrecioUnitario MONEY NOT NULL
            , Existencias INT NOT NULL
            , Disponible BIT NOT NULL
        );

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @envioACoordinar = @false;

        -- validaciones
        IF (@inIdMetodoEntrega IS NOT NULL)
        BEGIN
            SELECT @costoEnvio = ME.CostoEnvio
                , @requiereDireccion = ME.FlagRequiereDireccion
            FROM dbo.MetodoEntrega AS ME
            WHERE (ME.IdMetodoEntrega = @inIdMetodoEntrega);

            IF (@requiereDireccion IS NULL)
            BEGIN
                SET @outResultCode = 50051; -- método de entrega no válido
                RETURN;
            END;

            SET @envioACoordinar = CASE
                    WHEN (@requiereDireccion = @true) AND (@costoEnvio IS NULL) THEN @true
                    ELSE @false
                END;
        END;

        INSERT INTO @lineas (
            IdCarritoDetalle
            , IdProductoTalla
            , IdProducto
            , Nombre
            , RutaImagen
            , Talla
            , Cantidad
            , PrecioUnitario
            , Existencias
            , Disponible
        )
        SELECT CD.IdCarritoDetalle
            , CD.IdProductoTalla
            , P.IdProducto
            , P.Nombre
            , P.RutaImagen
            , T.Nombre
            , CD.Cantidad
            , P.Precio
            , CASE
                WHEN (P.FlagActivo = @true) THEN PT.Cantidad
                ELSE @sinExistencias
              END
            , CASE
                WHEN (P.FlagActivo = @true) AND (PT.Cantidad >= CD.Cantidad) THEN @true
                ELSE @false
              END
        FROM dbo.CarritoDetalle AS CD
        INNER JOIN dbo.ProductoTalla AS PT
            ON (PT.IdProductoTalla = CD.IdProductoTalla)
        INNER JOIN dbo.Producto AS P
            ON (P.IdProducto = PT.IdProducto)
        INNER JOIN dbo.Talla AS T
            ON (T.IdTalla = PT.IdTalla)
        WHERE (CD.IdUsuario = @inIdUsuario);

        SELECT @subtotalProductos = ISNULL(SUM(L.PrecioUnitario * L.Cantidad), 0)
        FROM @lineas AS L
        WHERE (L.Disponible = @true);

        -- primer resultado: líneas del carrito (GP008 restricción 1).
        -- Vacío = "Su carrito está vacío"
        SELECT L.IdCarritoDetalle
            , L.IdProductoTalla
            , L.IdProducto
            , L.Nombre
            , L.RutaImagen
            , L.Talla
            , L.Cantidad
            , L.PrecioUnitario
            , (L.PrecioUnitario * L.Cantidad) AS Subtotal
            , L.Existencias
            , L.Disponible
        FROM @lineas AS L
        ORDER BY L.Disponible DESC -- los no disponibles al final
            , L.IdCarritoDetalle;

        -- segundo resultado: desglose del costo (GP020 paso 2.4)
        SELECT @subtotalProductos AS SubtotalProductos
            , @costoEnvio AS CostoEnvio
            , @envioACoordinar AS EnvioACoordinar
            , (@subtotalProductos + ISNULL(@costoEnvio, 0)) AS Total
            , ISNULL((SELECT SUM(L.Cantidad) FROM @lineas AS L), 0) AS CantidadArticulos
            , CASE
                WHEN EXISTS (SELECT 1 FROM @lineas AS L WHERE (L.Disponible = @false)) THEN @true
                ELSE @false
              END AS HayNoDisponibles;

    END TRY
    BEGIN CATCH

        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION; -- deshace lo que quedó a medias
        END;

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-- ============================================================================
-- spModificarCarrito
-- ============================================================================
CREATE OR ALTER PROCEDURE dbo.spModificarCarrito
    @inIdUsuario INT -- cliente con sesión iniciada
    , @inIdCarritoDetalle INT -- línea del carrito
    , @inCantidad INT -- nueva cantidad
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP009 Modificar carrito: cambia la cantidad de una línea. Para quitarla se
usa spQuitarDelCarrito. Si la cantidad no es válida o supera las
existencias, no se cambia nada y se conserva la anterior (flujo alterno 1).
Después el backend vuelve a llamar spListarCarrito para recalcular (restricción 2).

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spModificarCarrito
        @inIdUsuario = 2
        , @inIdCarritoDetalle = 1
        , @inCantidad = 2
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1;

        -- variables de uso general
        DECLARE @existencias INT
            , @flagActivo BIT;

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito

        -- validaciones
        IF (@inCantidad IS NULL)
            OR (@inCantidad <= 0)
        BEGIN
            SET @outResultCode = 50046; -- cantidad inválida
            RETURN;
        END;

        -- la línea debe ser de este cliente
        SELECT @existencias = PT.Cantidad
            , @flagActivo = P.FlagActivo
        FROM dbo.CarritoDetalle AS CD
        INNER JOIN dbo.ProductoTalla AS PT
            ON (PT.IdProductoTalla = CD.IdProductoTalla)
        INNER JOIN dbo.Producto AS P
            ON (P.IdProducto = PT.IdProducto)
        WHERE (CD.IdCarritoDetalle = @inIdCarritoDetalle)
            AND (CD.IdUsuario = @inIdUsuario);

        IF (@flagActivo IS NULL)
        BEGIN
            SET @outResultCode = 50049; -- el producto no está en el carrito
            RETURN;
        END;

        IF (@flagActivo <> @true)
        BEGIN
            SET @outResultCode = 50011; -- producto eliminado: solo se puede quitar
            RETURN;
        END;

        -- GP009 restricción 1: no puede superar las existencias
        IF (@inCantidad > @existencias)
        BEGIN
            SET @outResultCode = 50048; -- supera las existencias

            SELECT @existencias AS Existencias;
            RETURN;
        END;

        UPDATE dbo.CarritoDetalle
        SET Cantidad = @inCantidad
        WHERE (IdCarritoDetalle = @inIdCarritoDetalle)
            AND (IdUsuario = @inIdUsuario);

    END TRY
    BEGIN CATCH

        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION; -- deshace lo que quedó a medias
        END;

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-- ============================================================================
-- spQuitarDelCarrito
-- ============================================================================
CREATE OR ALTER PROCEDURE dbo.spQuitarDelCarrito
    @inIdUsuario INT -- cliente con sesión iniciada
    , @inIdCarritoDetalle INT -- línea del carrito que se quita
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP009 Modificar carrito: quitar un producto. Si era el único, el carrito
queda vacío (flujo alterno 2: CantidadArticulos = 0).
No afecta el inventario.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spQuitarDelCarrito
        @inIdUsuario = 2
        , @inIdCarritoDetalle = 1
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito

        -- validaciones: la línea debe ser de este cliente
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.CarritoDetalle AS CD
            WHERE (CD.IdCarritoDetalle = @inIdCarritoDetalle)
                AND (CD.IdUsuario = @inIdUsuario)
        )
        BEGIN
            SET @outResultCode = 50049; -- el producto no está en el carrito
            RETURN;
        END;

        DELETE FROM dbo.CarritoDetalle
        WHERE (IdCarritoDetalle = @inIdCarritoDetalle)
            AND (IdUsuario = @inIdUsuario);

        -- primer resultado: indicador del carrito
        SELECT ISNULL(SUM(CD.Cantidad), 0) AS CantidadArticulos
        FROM dbo.CarritoDetalle AS CD
        WHERE (CD.IdUsuario = @inIdUsuario);

    END TRY
    BEGIN CATCH

        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION; -- deshace lo que quedó a medias
        END;

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-- ============================================================================
-- spVaciarCarrito
-- ============================================================================
CREATE OR ALTER PROCEDURE dbo.spVaciarCarrito
    @inIdUsuario INT -- cliente con sesión iniciada
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP010 Eliminar carrito. La confirmación "¿Confirma que desea vaciar su
carrito?" (restricción 1) la pide el frontend. No afecta el inventario.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spVaciarCarrito
        @inIdUsuario = 2
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito

        -- validaciones: GP010 precondición 2, al menos un producto
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.CarritoDetalle AS CD
            WHERE (CD.IdUsuario = @inIdUsuario)
        )
        BEGIN
            SET @outResultCode = 50050; -- el carrito está vacío
            RETURN;
        END;

        DELETE FROM dbo.CarritoDetalle
        WHERE (IdUsuario = @inIdUsuario);

    END TRY
    BEGIN CATCH

        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION; -- deshace lo que quedó a medias
        END;

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-- ============================================================================
-- spListarOpcionesOrden
-- ============================================================================
CREATE OR ALTER PROCEDURE dbo.spListarOpcionesOrden
    @inIdUsuario INT -- cliente con sesión iniciada
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP011 Seleccionar método de pago y GP012 Seleccionar método de entrega:
opciones para la pantalla de generar la orden.
La tabla no guarda una "orden en proceso": lo elegido vive en la página
hasta GP014, donde spConfirmarOrden valida todo junto.
Reglas para el frontend (vienen como banderas):
  - FlagRequiereDireccion = 1: pedir una dirección (GP012 restricción 2).
  - FlagSoloRetiro = 1 en el pago: deshabilitado si la entrega requiere
    dirección, con el texto "Disponible solo para retiro en el taller" (GP011).
  - FlagRequiereComprobante = 1: habilitar "Adjuntar comprobante" (GP013).

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spListarOpcionesOrden
        @inIdUsuario = 2
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1;

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito

        -- primer resultado: métodos de entrega (GP012 restricción 1)
        SELECT ME.IdMetodoEntrega
            , ME.Nombre
            , ME.FlagRequiereDireccion
            , ME.CostoEnvio -- NULL = envío a coordinar (GP020)
        FROM dbo.MetodoEntrega AS ME
        ORDER BY ME.IdMetodoEntrega;

        -- segundo resultado: métodos de pago (GP011)
        SELECT MP.IdMetodoPago
            , MP.Nombre
            , MP.FlagRequiereComprobante
            , MP.FlagSoloRetiro
        FROM dbo.MetodoPago AS MP
        ORDER BY MP.IdMetodoPago;

        -- tercer resultado: direcciones del cliente (vacío = GP012 flujo alterno:
        -- ir a agregar dirección)
        SELECT D.IdDireccion
            , PR.Nombre AS Provincia
            , D.Canton
            , D.Distrito
            , D.OtrasSenas
        FROM dbo.Direccion AS D
        INNER JOIN dbo.Provincia AS PR
            ON (PR.IdProvincia = D.IdProvincia)
        WHERE (D.IdUsuario = @inIdUsuario)
            AND (D.FlagActivo = @true)
        ORDER BY D.FechaCreacion DESC
            , D.IdDireccion DESC;

    END TRY
    BEGIN CATCH

        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION; -- deshace lo que quedó a medias
        END;

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-- ============================================================================
-- spConfirmarOrden
-- ============================================================================
CREATE OR ALTER PROCEDURE dbo.spConfirmarOrden
    @inIdUsuario INT -- cliente con sesión iniciada
    , @inIdMetodoPago INT -- GP011
    , @inIdMetodoEntrega INT -- GP012
    , @inIdDireccion INT -- GP012: obligatoria si la entrega es con envío; se ignora en retiro
    , @inRutaComprobante NVARCHAR(260) -- GP013: uploads/comprobantes/archivo.jpg (NULL si no aplica)
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP014 Confirmar orden de compra (incluye lo elegido en GP011, GP012 y GP013).

GP014 restricción 1 (ACID): todo pasa en UNA transacción. Las filas de
ProductoTalla del carrito se bloquean (UPDLOCK, HOLDLOCK) antes de revisar
las existencias, así si dos clientes piden el mismo producto único, el
segundo espera a que el primero termine y luego ve que ya no hay: se vende
al primero que confirma (criterio 2).

Flujo alterno 1: si algún producto ya no alcanza, no se registra la orden ni
se descuenta nada, y se devuelven las líneas que fallaron (código 50055 + datos).
Flujo alterno 2: si falta un dato (pago, entrega, dirección o comprobante),
se indica cuál con su propio código.

El comprobante: el backend guarda primero el archivo (png/jpg, máx. 5 MB,
GP013 restricción 1) y manda la ruta. Si este SP devuelve error, el backend
borra ese archivo.

El monto final queda guardado en la orden (GP020 postcondición 2).
CostoEnvio NULL = envío a coordinar; el total incluye solo los productos.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spConfirmarOrden
        @inIdUsuario = 2
        , @inIdMetodoPago = 1
        , @inIdMetodoEntrega = 1
        , @inIdDireccion = 1
        , @inRutaComprobante = N'uploads/comprobantes/2-1731600000000.jpg'
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0
            , @estadoPendiente INT = 1; -- "Pendiente de confirmación" (GP014 restricción 2)

        -- variables de uso general
        DECLARE @requiereComprobante BIT
            , @soloRetiro BIT
            , @requiereDireccion BIT
            , @costoEnvio MONEY
            , @direccionTexto NVARCHAR(400)
            , @rutaComprobante NVARCHAR(260)
            , @subtotalProductos MONEY
            , @total MONEY
            , @idPedido INT;

        -- líneas del carrito, leídas con bloqueo dentro de la transacción
        DECLARE @lineas TABLE (
            IdCarritoDetalle INT NOT NULL PRIMARY KEY
            , IdProductoTalla INT NOT NULL
            , IdProducto INT NOT NULL
            , NombreProducto NVARCHAR(100) NOT NULL
            , NombreTalla NVARCHAR(16) NOT NULL
            , PrecioUnitario MONEY NOT NULL
            , Cantidad INT NOT NULL
            , Existencias INT NOT NULL
            , FlagActivo BIT NOT NULL
        );

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @rutaComprobante = NULLIF(LTRIM(RTRIM(@inRutaComprobante)), N'');

        -- validaciones (GP014 paso 2.1: la información debe estar completa)
        -- GP014 precondición 2: carrito con al menos un producto
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.CarritoDetalle AS CD
            WHERE (CD.IdUsuario = @inIdUsuario)
        )
        BEGIN
            SET @outResultCode = 50050; -- el carrito está vacío
            RETURN;
        END;

        SELECT @requiereComprobante = MP.FlagRequiereComprobante
            , @soloRetiro = MP.FlagSoloRetiro
        FROM dbo.MetodoPago AS MP
        WHERE (MP.IdMetodoPago = @inIdMetodoPago);

        SELECT @requiereDireccion = ME.FlagRequiereDireccion
            , @costoEnvio = ME.CostoEnvio
        FROM dbo.MetodoEntrega AS ME
        WHERE (ME.IdMetodoEntrega = @inIdMetodoEntrega);

        -- GP011 criterio 1 / GP012: un método de pago y uno de entrega válidos
        IF (@requiereComprobante IS NULL)
            OR (@requiereDireccion IS NULL)
        BEGIN
            SET @outResultCode = 50051; -- falta o no existe el método de pago o de entrega
            RETURN;
        END;

        -- GP011 restricción 2: efectivo solo con retiro en el taller
        IF (@soloRetiro = @true)
            AND (@requiereDireccion = @true)
        BEGIN
            SET @outResultCode = 50053; -- efectivo solo para retiro
            RETURN;
        END;

        -- GP012 restricción 2: dirección obligatoria para métodos con envío.
        -- Se guarda una copia en texto (GP005 y GP006: el pedido conserva su dirección)
        IF (@requiereDireccion = @true)
        BEGIN
            IF (@inIdDireccion IS NULL)
            BEGIN
                SET @outResultCode = 50052; -- falta la dirección
                RETURN;
            END;

            SELECT @direccionTexto = D.OtrasSenas
                + N', ' + D.Distrito
                + N', ' + D.Canton
                + N', ' + PR.Nombre
            FROM dbo.Direccion AS D
            INNER JOIN dbo.Provincia AS PR
                ON (PR.IdProvincia = D.IdProvincia)
            WHERE (D.IdDireccion = @inIdDireccion)
                AND (D.IdUsuario = @inIdUsuario)
                AND (D.FlagActivo = @true);

            IF (@direccionTexto IS NULL)
            BEGIN
                SET @outResultCode = 50044; -- la dirección no existe
                RETURN;
            END;
        END
        ELSE
        BEGIN
            SET @direccionTexto = NULL; -- retiro en el taller: no se pide dirección
        END;

        -- GP013 restricción 2: comprobante obligatorio con SINPE Móvil.
        -- Si el método no lo usa, se ignora (efectivo: "Pago en efectivo al retirar")
        IF (@requiereComprobante = @true)
            AND (@rutaComprobante IS NULL)
        BEGIN
            SET @outResultCode = 50054; -- falta el comprobante
            RETURN;
        END;

        IF (@requiereComprobante = @false)
        BEGIN
            SET @rutaComprobante = NULL;
        END;

        IF (@rutaComprobante IS NOT NULL)
            AND (LOWER(@rutaComprobante) NOT LIKE N'%.png')
            AND (LOWER(@rutaComprobante) NOT LIKE N'%.jpg')
            AND (LOWER(@rutaComprobante) NOT LIKE N'%.jpeg')
        BEGIN
            SET @outResultCode = 50027; -- formato de imagen no permitido
            RETURN;
        END;

        BEGIN TRANSACTION tConfirmarOrden;

            -- GP014 paso 2.2: lee el carrito y BLOQUEA las existencias de esos
            -- productos hasta el COMMIT. Otra confirmación del mismo producto espera aquí
            INSERT INTO @lineas (
                IdCarritoDetalle
                , IdProductoTalla
                , IdProducto
                , NombreProducto
                , NombreTalla
                , PrecioUnitario
                , Cantidad
                , Existencias
                , FlagActivo
            )
            SELECT CD.IdCarritoDetalle
                , CD.IdProductoTalla
                , P.IdProducto
                , P.Nombre
                , T.Nombre
                , P.Precio -- precio vigente (GP020 paso 2.1)
                , CD.Cantidad
                , PT.Cantidad
                , P.FlagActivo
            FROM dbo.CarritoDetalle AS CD WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.ProductoTalla AS PT WITH (UPDLOCK, HOLDLOCK)
                ON (PT.IdProductoTalla = CD.IdProductoTalla)
            INNER JOIN dbo.Producto AS P WITH (HOLDLOCK)
                ON (P.IdProducto = PT.IdProducto)
            INNER JOIN dbo.Talla AS T
                ON (T.IdTalla = PT.IdTalla)
            WHERE (CD.IdUsuario = @inIdUsuario);

            -- el carrito pudo vaciarse mientras tanto (por ejemplo, confirmó en otra pestaña)
            IF NOT EXISTS (SELECT 1 FROM @lineas)
            BEGIN
                ROLLBACK TRANSACTION;
                SET @outResultCode = 50050; -- el carrito está vacío
                RETURN;
            END;

            -- GP014 flujo alterno 1 y criterio 1: algún producto ya no alcanza
            IF EXISTS (
                SELECT 1
                FROM @lineas AS L
                WHERE (L.FlagActivo = @false)
                    OR (L.Existencias < L.Cantidad)
            )
            BEGIN
                ROLLBACK TRANSACTION; -- no se registra ni se descuenta nada
                SET @outResultCode = 50055; -- productos no disponibles

                -- datos: cuáles productos fallaron, para marcarlos en el carrito
                SELECT L.IdCarritoDetalle
                    , L.IdProducto
                    , L.NombreProducto
                    , L.NombreTalla
                    , L.Cantidad
                    , CASE
                        WHEN (L.FlagActivo = @true) THEN L.Existencias
                        ELSE 0
                      END AS Disponibles
                FROM @lineas AS L
                WHERE (L.FlagActivo = @false)
                    OR (L.Existencias < L.Cantidad);
                RETURN;
            END;

            -- GP020 restricción 1: suma de (precio × cantidad) + envío si aplica
            SELECT @subtotalProductos = SUM(L.PrecioUnitario * L.Cantidad)
            FROM @lineas AS L;

            SET @total = @subtotalProductos + ISNULL(@costoEnvio, 0);

            -- GP014 paso 2.3: la orden, con estado "Pendiente de confirmación"
            INSERT INTO dbo.Pedido (
                IdUsuario
                , IdEstadoPedido
                , IdMetodoPago
                , IdMetodoEntrega
                , DireccionEntrega
                , SubtotalProductos
                , CostoEnvio
                , Total
                , MotivoEstado
                , FechaCreacion
            )
            VALUES (
                @inIdUsuario
                , @estadoPendiente
                , @inIdMetodoPago
                , @inIdMetodoEntrega
                , @direccionTexto
                , @subtotalProductos
                , @costoEnvio
                , @total
                , NULL
                , GETDATE()
            );

            SET @idPedido = SCOPE_IDENTITY(); -- número de pedido (criterio 3)

            -- el detalle guarda nombre, talla y precio del momento de la compra
            -- (ERS 2.4: el historial de ventas debe conservar los detalles)
            INSERT INTO dbo.PedidoDetalle (
                IdPedido
                , IdProductoTalla
                , NombreProducto
                , NombreTalla
                , PrecioUnitario
                , Cantidad
                , Subtotal
            )
            SELECT @idPedido
                , L.IdProductoTalla
                , L.NombreProducto
                , L.NombreTalla
                , L.PrecioUnitario
                , L.Cantidad
                , (L.PrecioUnitario * L.Cantidad)
            FROM @lineas AS L;

            -- GP014 paso 2.2 y postcondición 2: descuenta del inventario
            UPDATE PT
            SET PT.Cantidad = PT.Cantidad - L.Cantidad
            FROM dbo.ProductoTalla AS PT
            INNER JOIN @lineas AS L
                ON (L.IdProductoTalla = PT.IdProductoTalla);

            -- GP013 restricción 3: el comprobante queda asociado solo a esta orden
            IF (@rutaComprobante IS NOT NULL)
            BEGIN
                INSERT INTO dbo.Comprobante (
                    IdPedido
                    , RutaArchivo
                    , FechaSubida
                )
                VALUES (
                    @idPedido
                    , @rutaComprobante
                    , GETDATE()
                );
            END;

            -- primer registro del historial del pedido (GP018)
            INSERT INTO dbo.HistorialEstadoPedido (
                IdPedido
                , IdEstadoPedido
                , IdUsuario
                , Comentario
                , FechaHora
            )
            VALUES (
                @idPedido
                , @estadoPendiente
                , @inIdUsuario
                , N'Orden registrada por el cliente'
                , GETDATE()
            );

            -- GP014 paso 2.4: vacía el carrito
            DELETE FROM dbo.CarritoDetalle
            WHERE (IdUsuario = @inIdUsuario);

        COMMIT TRANSACTION tConfirmarOrden;

        -- primer resultado: número de pedido y montos (GP014 paso 2.5).
        -- RutaComprobante NULL = no se guardó (pago en efectivo): el backend
        -- borra el archivo si el navegador mandó uno de todos modos
        SELECT @idPedido AS IdPedido
            , @subtotalProductos AS SubtotalProductos
            , @costoEnvio AS CostoEnvio
            , @total AS Total
            , @rutaComprobante AS RutaComprobante;

        -- segundo resultado: productos que cambiaron de existencias, para que el
        -- backend llame avisarCatalogo(idProducto) (CP010)
        SELECT DISTINCT L.IdProducto
        FROM @lineas AS L;

    END TRY
    BEGIN CATCH

        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION; -- deshace lo que quedó a medias
        END;

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-- ============================================================================
-- spListarPedidosAdmin
-- ============================================================================
CREATE OR ALTER PROCEDURE dbo.spListarPedidosAdmin
    @inIdEstadoPedido INT -- filtro por estado (NULL = todos)
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP015 Visualizar comprobantes por administrador, paso 2.2: lista de pedidos
con número, cliente, fecha, total y estado. Solo para la administradora
(restricción 1: el backend revisa la sesión). El detalle y el comprobante
se ven con spObtenerPedido.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spListarPedidosAdmin
        @inIdEstadoPedido = NULL
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0;

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito

        -- primer resultado: pedidos, el más reciente primero.
        -- Vacío y sin filtro = "Aún no hay pedidos registrados"
        SELECT P.IdPedido
            , P.FechaCreacion
            , U.Nombre AS Cliente
            , P.Total
            , P.IdEstadoPedido
            , EP.Nombre AS Estado
            , MP.Nombre AS MetodoPago
            , ME.Nombre AS MetodoEntrega
            , CASE
                WHEN (CO.IdComprobante IS NOT NULL) THEN @true
                ELSE @false
              END AS TieneComprobante
        FROM dbo.Pedido AS P
        INNER JOIN dbo.Usuario AS U
            ON (U.IdUsuario = P.IdUsuario)
        INNER JOIN dbo.EstadoPedido AS EP
            ON (EP.IdEstadoPedido = P.IdEstadoPedido)
        INNER JOIN dbo.MetodoPago AS MP
            ON (MP.IdMetodoPago = P.IdMetodoPago)
        INNER JOIN dbo.MetodoEntrega AS ME
            ON (ME.IdMetodoEntrega = P.IdMetodoEntrega)
        LEFT JOIN dbo.Comprobante AS CO
            ON (CO.IdPedido = P.IdPedido)
        WHERE (@inIdEstadoPedido IS NULL)
            OR (P.IdEstadoPedido = @inIdEstadoPedido)
        ORDER BY P.FechaCreacion DESC
            , P.IdPedido DESC;

        -- segundo resultado: estados, para el filtro
        SELECT EP.IdEstadoPedido
            , EP.Nombre
        FROM dbo.EstadoPedido AS EP
        ORDER BY EP.IdEstadoPedido;

    END TRY
    BEGIN CATCH

        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION; -- deshace lo que quedó a medias
        END;

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-- ============================================================================
-- spListarPedidosCliente
-- ============================================================================
CREATE OR ALTER PROCEDURE dbo.spListarPedidosCliente
    @inIdUsuario INT -- cliente con sesión iniciada
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP018 Consultar historial de pedido, paso 2.1: los pedidos del cliente, del
más reciente al más antiguo, con número, fecha, estado y total.
Solo los suyos (restricción 1). El detalle se ve con spObtenerPedido.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spListarPedidosCliente
        @inIdUsuario = 2
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito

        -- primer resultado: vacío = "Aún no ha realizado pedidos"
        SELECT P.IdPedido
            , P.FechaCreacion
            , P.IdEstadoPedido
            , EP.Nombre AS Estado
            , P.MotivoEstado -- motivo si fue rechazado o cancelado (GP019)
            , P.Total
        FROM dbo.Pedido AS P
        INNER JOIN dbo.EstadoPedido AS EP
            ON (EP.IdEstadoPedido = P.IdEstadoPedido)
        WHERE (P.IdUsuario = @inIdUsuario)
        ORDER BY P.FechaCreacion DESC
            , P.IdPedido DESC;

    END TRY
    BEGIN CATCH

        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION; -- deshace lo que quedó a medias
        END;

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-- ============================================================================
-- spObtenerPedido
-- ============================================================================
CREATE OR ALTER PROCEDURE dbo.spObtenerPedido
    @inIdUsuario INT -- usuario con sesión iniciada (cliente o administradora)
    , @inIdPedido INT -- pedido que se consulta
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
Detalle de un pedido. Lo usan dos requerimientos:
  - GP015 paso 4.1 (administradora): detalle + comprobante.
  - GP018 paso 4.1 (cliente): solo si el pedido es suyo (restricción 1).
El SP revisa en la tabla Usuario si quien pide es administradora; si es
cliente y el pedido no es suyo, responde "no existe" (no revela nada).

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spObtenerPedido
        @inIdUsuario = 1
        , @inIdPedido = 1
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0;

        -- variables de uso general
        DECLARE @esAdministrador BIT
            , @requiereDireccion BIT
            , @estadoActual INT;

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito

        SELECT @esAdministrador = U.EsAdministrador
        FROM dbo.Usuario AS U
        WHERE (U.IdUsuario = @inIdUsuario)
            AND (U.FlagActivo = @true);

        -- validaciones
        IF (@esAdministrador IS NULL)
            OR NOT EXISTS (
                SELECT 1
                FROM dbo.Pedido AS P
                WHERE (P.IdPedido = @inIdPedido)
                    AND (
                        (@esAdministrador = @true)
                        OR (P.IdUsuario = @inIdUsuario)
                    )
            )
        BEGIN
            SET @outResultCode = 50056; -- el pedido no existe
            RETURN;
        END;

        SELECT @estadoActual = P.IdEstadoPedido
            , @requiereDireccion = ME.FlagRequiereDireccion
        FROM dbo.Pedido AS P
        INNER JOIN dbo.MetodoEntrega AS ME
            ON (ME.IdMetodoEntrega = P.IdMetodoEntrega)
        WHERE (P.IdPedido = @inIdPedido);

        -- primer resultado: encabezado (GP015 restricción 2).
        -- RutaComprobante NULL y pago en efectivo = "Pago en efectivo al retirar en el taller"
        SELECT P.IdPedido
            , P.FechaCreacion
            , P.IdEstadoPedido
            , EP.Nombre AS Estado
            , P.MotivoEstado
            , U.IdUsuario AS IdCliente
            , U.Nombre AS Cliente
            , U.Correo
            , U.Telefono
            , MP.Nombre AS MetodoPago
            , MP.FlagRequiereComprobante
            , ME.Nombre AS MetodoEntrega
            , ME.FlagRequiereDireccion
            , P.DireccionEntrega
            , P.SubtotalProductos
            , P.CostoEnvio -- NULL = envío a coordinar
            , P.Total
            , CO.RutaArchivo AS RutaComprobante
            , CO.FechaSubida AS FechaComprobante
        FROM dbo.Pedido AS P
        INNER JOIN dbo.Usuario AS U
            ON (U.IdUsuario = P.IdUsuario)
        INNER JOIN dbo.EstadoPedido AS EP
            ON (EP.IdEstadoPedido = P.IdEstadoPedido)
        INNER JOIN dbo.MetodoPago AS MP
            ON (MP.IdMetodoPago = P.IdMetodoPago)
        INNER JOIN dbo.MetodoEntrega AS ME
            ON (ME.IdMetodoEntrega = P.IdMetodoEntrega)
        LEFT JOIN dbo.Comprobante AS CO
            ON (CO.IdPedido = P.IdPedido)
        WHERE (P.IdPedido = @inIdPedido);

        -- segundo resultado: productos, con los datos guardados al comprar
        SELECT PD.IdPedidoDetalle
            , PD.IdProductoTalla
            , PT.IdProducto
            , PD.NombreProducto
            , PD.NombreTalla
            , PD.PrecioUnitario
            , PD.Cantidad
            , PD.Subtotal
            , PR.RutaImagen
        FROM dbo.PedidoDetalle AS PD
        INNER JOIN dbo.ProductoTalla AS PT
            ON (PT.IdProductoTalla = PD.IdProductoTalla)
        INNER JOIN dbo.Producto AS PR
            ON (PR.IdProducto = PT.IdProducto)
        WHERE (PD.IdPedido = @inIdPedido)
        ORDER BY PD.IdPedidoDetalle;

        -- tercer resultado: historial de estados con fecha, hora y motivo
        -- (GP016 paso 2.1, GP017 paso 4.1, GP019 restricción 2)
        SELECT H.FechaHora
            , H.IdEstadoPedido
            , EP.Nombre AS Estado
            , H.Comentario
        FROM dbo.HistorialEstadoPedido AS H
        INNER JOIN dbo.EstadoPedido AS EP
            ON (EP.IdEstadoPedido = H.IdEstadoPedido)
        WHERE (H.IdPedido = @inIdPedido)
        ORDER BY H.FechaHora
            , H.IdHistorialEstadoPedido;

        -- cuarto resultado: estados a los que puede pasar según el estado actual
        -- y el método de entrega (GP017 paso 2.1). Vacío para clientes
        SELECT TE.IdEstadoNuevo AS IdEstadoPedido
            , EP.Nombre
            , EP.FlagRequiereMotivo -- pedir motivo (Rechazado)
            , EP.FlagDevuelveInventario -- pedir confirmación (Cancelado)
        FROM dbo.TransicionEstadoPedido AS TE
        INNER JOIN dbo.EstadoPedido AS EP
            ON (EP.IdEstadoPedido = TE.IdEstadoNuevo)
        WHERE (@esAdministrador = @true)
            AND (TE.IdEstadoActual = @estadoActual)
            AND (
                (TE.FlagSoloEnvio = @false)
                OR (@requiereDireccion = @true)
            )
            AND (
                (TE.FlagSoloRetiro = @false)
                OR (@requiereDireccion = @false)
            )
        ORDER BY TE.IdEstadoNuevo;

    END TRY
    BEGIN CATCH

        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION; -- deshace lo que quedó a medias
        END;

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-- ============================================================================
-- spCambiarEstadoPedido
-- ============================================================================
CREATE OR ALTER PROCEDURE dbo.spCambiarEstadoPedido
    @inIdUsuario INT -- administradora con sesión iniciada
    , @inIdPedido INT -- pedido que cambia de estado
    , @inIdEstadoNuevo INT -- estado al que pasa
    , @inMotivo NVARCHAR(300) -- obligatorio si el estado lo pide (Rechazado)
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP016 Confirmar pedido por administrador (Confirmado o Rechazado) y
GP017 Actualizar estado de pedido. Un solo SP porque las reglas salen de
las tablas, sin números fijos:
  - TransicionEstadoPedido: solo transiciones válidas, siempre hacia adelante
    (GP016 restricción 2, GP017 restricción 2). FlagSoloEnvio / FlagSoloRetiro
    según el método de entrega ("Enviado" o "Listo para retiro").
  - EstadoPedido.FlagRequiereMotivo: motivo obligatorio (GP016 restricción 3).
  - EstadoPedido.FlagDevuelveInventario: devuelve los productos al inventario
    (GP016 flujo alterno 1, GP017 restricción 3).
Registra fecha y hora en el historial y deja la notificación lista para que
el backend envíe el correo (GP019). Todo en una transacción con el pedido
bloqueado, así dos clics seguidos no cambian el estado dos veces.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spCambiarEstadoPedido
        @inIdUsuario = 1
        , @inIdPedido = 1
        , @inIdEstadoNuevo = 8
        , @inMotivo = N'El comprobante no corresponde al monto del pedido'
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0
            , @sinIntentos INT = 0;

        -- variables de uso general
        DECLARE @motivo NVARCHAR(300)
            , @nombreEstado NVARCHAR(32)
            , @requiereMotivo BIT
            , @devuelveInventario BIT
            , @estadoActual INT
            , @requiereDireccion BIT
            , @idCliente INT
            , @idNotificacion INT
            , @numeroPedido NVARCHAR(12);

        -- productos que vuelven al inventario, para avisar al catálogo (CP010)
        DECLARE @productosDevueltos TABLE (
            IdProducto INT NOT NULL PRIMARY KEY
        );

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @motivo = NULLIF(LTRIM(RTRIM(@inMotivo)), N'');
        SET @numeroPedido = CAST(@inIdPedido AS NVARCHAR(12));

        -- validaciones
        -- GP016 restricción 1: solo la administradora
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Usuario AS U
            WHERE (U.IdUsuario = @inIdUsuario)
                AND (U.EsAdministrador = @true)
                AND (U.FlagActivo = @true)
        )
        BEGIN
            SET @outResultCode = 50034; -- no es la administradora (mismo código que usa el backend)
            RETURN;
        END;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Pedido AS P
            WHERE (P.IdPedido = @inIdPedido)
        )
        BEGIN
            SET @outResultCode = 50056; -- el pedido no existe
            RETURN;
        END;

        SELECT @nombreEstado = EP.Nombre
            , @requiereMotivo = EP.FlagRequiereMotivo
            , @devuelveInventario = EP.FlagDevuelveInventario
        FROM dbo.EstadoPedido AS EP
        WHERE (EP.IdEstadoPedido = @inIdEstadoNuevo);

        IF (@nombreEstado IS NULL)
        BEGIN
            SET @outResultCode = 50057; -- cambio de estado no permitido
            RETURN;
        END;

        -- GP016 restricción 3: para rechazar es obligatorio el motivo
        IF (@requiereMotivo = @true)
            AND (@motivo IS NULL)
        BEGIN
            SET @outResultCode = 50058; -- falta el motivo
            RETURN;
        END;

        BEGIN TRANSACTION tCambiarEstadoPedido;

            -- bloquea el pedido y lee su estado actual
            SELECT @estadoActual = P.IdEstadoPedido
                , @idCliente = P.IdUsuario
                , @requiereDireccion = ME.FlagRequiereDireccion
            FROM dbo.Pedido AS P WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.MetodoEntrega AS ME
                ON (ME.IdMetodoEntrega = P.IdMetodoEntrega)
            WHERE (P.IdPedido = @inIdPedido);

            -- GP017 criterio 1: solo transiciones válidas
            IF NOT EXISTS (
                SELECT 1
                FROM dbo.TransicionEstadoPedido AS TE
                WHERE (TE.IdEstadoActual = @estadoActual)
                    AND (TE.IdEstadoNuevo = @inIdEstadoNuevo)
                    AND (
                        (TE.FlagSoloEnvio = @false)
                        OR (@requiereDireccion = @true)
                    )
                    AND (
                        (TE.FlagSoloRetiro = @false)
                        OR (@requiereDireccion = @false)
                    )
            )
            BEGIN
                ROLLBACK TRANSACTION;
                SET @outResultCode = 50057; -- cambio de estado no permitido
                RETURN;
            END;

            -- Rechazado o Cancelado: los productos vuelven al inventario
            IF (@devuelveInventario = @true)
            BEGIN
                UPDATE PT
                SET PT.Cantidad = PT.Cantidad + D.Cantidad
                FROM dbo.ProductoTalla AS PT
                INNER JOIN (
                    SELECT PD.IdProductoTalla
                        , SUM(PD.Cantidad) AS Cantidad
                    FROM dbo.PedidoDetalle AS PD
                    WHERE (PD.IdPedido = @inIdPedido)
                    GROUP BY PD.IdProductoTalla
                ) AS D
                    ON (D.IdProductoTalla = PT.IdProductoTalla);

                INSERT INTO @productosDevueltos (
                    IdProducto
                )
                SELECT DISTINCT PT.IdProducto
                FROM dbo.PedidoDetalle AS PD
                INNER JOIN dbo.ProductoTalla AS PT
                    ON (PT.IdProductoTalla = PD.IdProductoTalla)
                WHERE (PD.IdPedido = @inIdPedido);
            END;

            UPDATE dbo.Pedido
            SET IdEstadoPedido = @inIdEstadoNuevo
                , MotivoEstado = COALESCE(@motivo, MotivoEstado)
            WHERE (IdPedido = @inIdPedido);

            -- GP016 paso 2.1 / GP017 paso 4.1: registra fecha y hora del cambio
            INSERT INTO dbo.HistorialEstadoPedido (
                IdPedido
                , IdEstadoPedido
                , IdUsuario
                , Comentario
                , FechaHora
            )
            VALUES (
                @inIdPedido
                , @inIdEstadoNuevo
                , @inIdUsuario
                , @motivo
                , GETDATE()
            );

            -- GP019: número de pedido, nuevo estado y motivo si lo hay; sin datos
            -- sensibles (restricción 3). El backend la envía por correo
            INSERT INTO dbo.Notificacion (
                IdPedido
                , Correo
                , Asunto
                , Mensaje
                , FlagEnviado
                , Intentos
                , FechaCreacion
            )
            SELECT @inIdPedido
                , U.Correo
                , N'Pedido #' + @numeroPedido + N': ' + @nombreEstado
                , N'Hola ' + U.Nombre + N', su pedido #' + @numeroPedido
                    + N' en Confecciones Capanni cambió al estado "' + @nombreEstado + N'".'
                    + CASE
                        WHEN (@motivo IS NOT NULL) THEN N' Motivo: ' + @motivo
                        ELSE N''
                      END
                , @false
                , @sinIntentos
                , GETDATE()
            FROM dbo.Usuario AS U
            WHERE (U.IdUsuario = @idCliente);

            SET @idNotificacion = SCOPE_IDENTITY();

        COMMIT TRANSACTION tCambiarEstadoPedido;

        -- primer resultado: el cambio hecho y la notificación por enviar
        SELECT @inIdPedido AS IdPedido
            , @inIdEstadoNuevo AS IdEstadoPedido
            , @nombreEstado AS Estado
            , @idCliente AS IdCliente
            , @idNotificacion AS IdNotificacion;

        -- segundo resultado: productos devueltos al inventario (vacío si no aplica),
        -- para avisarCatalogo (CP010)
        SELECT PD.IdProducto
        FROM @productosDevueltos AS PD;

    END TRY
    BEGIN CATCH

        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION; -- deshace lo que quedó a medias
        END;

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-- ============================================================================
-- spListarNotificacionesPendientes
-- ============================================================================
CREATE OR ALTER PROCEDURE dbo.spListarNotificacionesPendientes
    @inMaxIntentos INT -- después de esta cantidad de fallos ya no se reintenta
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP019 flujo alterno: si no se pudo enviar el correo, se reintenta.
El backend llama este SP cada cierto tiempo (por ejemplo, cada minuto) y
envía los correos que siguen pendientes. El estado del pedido igual es
visible en el historial aunque el correo falle.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spListarNotificacionesPendientes
        @inMaxIntentos = 5
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @false BIT = 0
            , @intentosPorDefecto INT = 5;

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito

        -- primer resultado: correos por enviar, los más viejos primero
        SELECT N.IdNotificacion
            , N.IdPedido
            , N.Correo
            , N.Asunto
            , N.Mensaje
            , N.Intentos
        FROM dbo.Notificacion AS N
        WHERE (N.FlagEnviado = @false)
            AND (N.Intentos < ISNULL(@inMaxIntentos, @intentosPorDefecto))
        ORDER BY N.FechaCreacion
            , N.IdNotificacion;

    END TRY
    BEGIN CATCH

        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION; -- deshace lo que quedó a medias
        END;

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-- ============================================================================
-- spRegistrarEnvioNotificacion
-- ============================================================================
CREATE OR ALTER PROCEDURE dbo.spRegistrarEnvioNotificacion
    @inIdNotificacion INT -- notificación que se intentó enviar
    , @inFlagEnviado BIT -- 1 = el correo salió, 0 = falló
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP019 postcondición 2: el envío queda registrado en el sistema.
Cada intento suma 1 a Intentos; si salió, se marca enviado con fecha y hora.
Los fallos (flujo alterno) quedan pendientes para el siguiente reintento.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spRegistrarEnvioNotificacion
        @inIdNotificacion = 1
        , @inFlagEnviado = 1
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1;

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito

        -- validaciones
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Notificacion AS N
            WHERE (N.IdNotificacion = @inIdNotificacion)
        )
        BEGIN
            SET @outResultCode = 50059; -- la notificación no existe
            RETURN;
        END;

        UPDATE dbo.Notificacion
        SET Intentos = Intentos + 1
            , FlagEnviado = CASE
                    WHEN (@inFlagEnviado = @true) THEN @true
                    ELSE FlagEnviado
                END
            , FechaEnvio = CASE
                    WHEN (@inFlagEnviado = @true) THEN GETDATE()
                    ELSE FechaEnvio
                END
        WHERE (IdNotificacion = @inIdNotificacion);

    END TRY
    BEGIN CATCH

        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION; -- deshace lo que quedó a medias
        END;

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

