CREATE OR ALTER PROCEDURE dbo.spActualizarProducto
    @inIdUsuario INT -- quién edita, debe ser administradora
    , @inIP VARCHAR(64) -- ip del cliente, para la bitácora
    , @inIdProducto INT -- producto que se edita
    , @inIdCategoria INT -- nueva categoría
    , @inNombre NVARCHAR(100) -- nuevo nombre
    , @inDescripcion NVARCHAR(500) -- nueva descripción (opcional)
    , @inPrecio MONEY -- nuevo precio
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GI005 Modificar producto.
Las existencias por talla se cambian con spActualizarDisponibilidad (GI007).
El UPDATE es atómico: si un cliente confirma una orden al mismo tiempo, una
de las dos operaciones espera a que la otra termine (GI005 restricción 2).

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spActualizarProducto
        @inIdUsuario = 1
        , @inIP = '127.0.0.1'
        , @inIdProducto = 1
        , @inIdCategoria = 1
        , @inNombre = N'Blusa floreada manga corta'
        , @inDescripcion = N'Blusa de algodón con estampado de flores'
        , @inPrecio = 13000
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0
            , @tipoOperacionModificar INT = 3; -- TipoOperacion "Modificar producto"

        -- variables de uso general
        DECLARE @esAdministrador BIT
            , @nombre NVARCHAR(100)
            , @descripcion NVARCHAR(500);

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @esAdministrador = @false;
        SET @nombre = LTRIM(RTRIM(ISNULL(@inNombre, '')));
        SET @descripcion = NULLIF(LTRIM(RTRIM(@inDescripcion)), '');

        -- validaciones de acceso
        SELECT @esAdministrador = U.EsAdministrador
        FROM dbo.Usuario AS U
        WHERE (U.IdUsuario = @inIdUsuario)
            AND (U.FlagActivo = @true);

        IF (@esAdministrador = @false)
        BEGIN
            SET @outResultCode = 50002; -- requiere rol de administración
            RETURN;
        END;

        -- el producto debe existir y no estar eliminado
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Producto AS P
            WHERE (P.IdProducto = @inIdProducto)
                AND (P.FlagActivo = @true)
        )
        BEGIN
            SET @outResultCode = 50011; -- producto no existe o fue eliminado
            RETURN;
        END;

        -- validaciones de campos (las mismas que al agregar)
        IF (@nombre = '')
        BEGIN
            SET @outResultCode = 50003; -- campo obligatorio vacío
            RETURN;
        END;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Categoria AS C
            WHERE (C.IdCategoria = @inIdCategoria)
        )
        BEGIN
            SET @outResultCode = 50007; -- categoría no existe
            RETURN;
        END;

        IF (@inPrecio IS NULL)
            OR (@inPrecio <= 0)
        BEGIN
            SET @outResultCode = 50008; -- precio inválido
            RETURN;
        END;

        -- variables para el preprocesamiento y la transacción
        DECLARE @huboCambio BIT
            , @jsonAntes NVARCHAR(MAX)
            , @jsonDespues NVARCHAR(MAX);

        -- preprocesamiento: compara lo recibido contra lo guardado.
        -- ISNULL evita que una descripción NULL esconda el cambio
        SET @huboCambio = @false;

        SELECT @huboCambio = CASE
                WHEN (P.IdCategoria <> @inIdCategoria)
                    OR (P.Nombre <> @nombre)
                    OR (ISNULL(P.Descripcion, N'') <> ISNULL(@descripcion, N''))
                    OR (P.Precio <> @inPrecio)
                THEN @true
                ELSE @false
              END
        FROM dbo.Producto AS P
        WHERE (P.IdProducto = @inIdProducto);

        -- si no cambió nada se sale con éxito y no se registra en bitácora
        IF (@huboCambio = @false)
        BEGIN
            RETURN;
        END;

        SET @jsonAntes = dbo.fnJsonProducto(@inIdProducto);

        -- transacción: cambio y bitácora van juntos
        BEGIN TRANSACTION tActualizarProducto;

            UPDATE dbo.Producto
            SET IdCategoria = @inIdCategoria
                , Nombre = @nombre
                , Descripcion = @descripcion
                , Precio = @inPrecio
            WHERE (IdProducto = @inIdProducto);

            SET @jsonDespues = dbo.fnJsonProducto(@inIdProducto);

            INSERT INTO dbo.Bitacora (
                IdUsuario
                , IdTipoOperacion
                , IP
                , DatosAntes
                , DatosDespues
            )
            VALUES (
                @inIdUsuario
                , @tipoOperacionModificar
                , @inIP
                , @jsonAntes
                , @jsonDespues
            );

        COMMIT TRANSACTION tActualizarProducto;

    END TRY
    BEGIN CATCH

        -- si quedó una transacción abierta, se deshace
        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION;
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
