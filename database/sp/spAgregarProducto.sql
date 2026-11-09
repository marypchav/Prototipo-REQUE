CREATE OR ALTER PROCEDURE dbo.spAgregarProducto
    @inIdUsuario INT -- quién agrega, debe ser administradora
    , @inIP VARCHAR(64) -- ip del cliente, para la bitácora
    , @inIdCategoria INT -- categoría de la prenda
    , @inNombre NVARCHAR(100) -- nombre del producto
    , @inDescripcion NVARCHAR(500) -- descripción (opcional)
    , @inPrecio MONEY -- precio en colones, mayor a 0
    , @inTallasJson NVARCHAR(MAX) -- tallas y existencias: [{"IdTalla":2,"Cantidad":1}, ...]
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GI002 Agregar producto.
La foto se sube después con spActualizarImagenProducto (GI003), por eso
se devuelve el IdProducto creado.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spAgregarProducto
        @inIdUsuario = 1
        , @inIP = '127.0.0.1'
        , @inIdCategoria = 1
        , @inNombre = N'Blusa floreada'
        , @inDescripcion = N'Blusa de algodón con estampado de flores'
        , @inPrecio = 12500
        , @inTallasJson = N'[{"IdTalla":2,"Cantidad":1},{"IdTalla":3,"Cantidad":2}]'
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0
            , @tipoOperacionAgregar INT = 2; -- TipoOperacion "Agregar producto"

        -- variables de uso general
        DECLARE @esAdministrador BIT
            , @nombre NVARCHAR(100)
            , @descripcion NVARCHAR(500)
            , @tallasJson NVARCHAR(MAX);

        -- tallas recibidas, ya separadas del JSON
        DECLARE @tallas TABLE (
            IdTalla INT NULL
            , Cantidad INT NULL
        );

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @esAdministrador = @false;
        SET @nombre = LTRIM(RTRIM(ISNULL(@inNombre, '')));
        SET @descripcion = NULLIF(LTRIM(RTRIM(@inDescripcion)), ''); -- vacía = NULL
        SET @tallasJson = LTRIM(RTRIM(ISNULL(@inTallasJson, '')));

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

        -- validaciones de campos
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

        -- GI002 restricción 1: precio positivo
        IF (@inPrecio IS NULL)
            OR (@inPrecio <= 0)
        BEGIN
            SET @outResultCode = 50008; -- precio inválido
            RETURN;
        END;

        -- el JSON de tallas debe ser un arreglo válido
        IF (ISNULL(ISJSON(@tallasJson), 0) = 0)
            OR (LEFT(@tallasJson, 1) <> '[')
        BEGIN
            SET @outResultCode = 50010; -- lista de tallas inválida
            RETURN;
        END;

        -- preprocesamiento: se separa el JSON en filas
        INSERT INTO @tallas (
            IdTalla
            , Cantidad
        )
        SELECT J.IdTalla
            , J.Cantidad
        FROM OPENJSON(@tallasJson)
        WITH (
            IdTalla INT '$.IdTalla'
            , Cantidad INT '$.Cantidad'
        ) AS J;

        -- al menos una talla, todas existentes en el catálogo y sin repetir
        IF NOT EXISTS (
                SELECT 1
                FROM @tallas
            )
            OR EXISTS (
                SELECT 1
                FROM @tallas AS TA
                WHERE NOT EXISTS (
                    SELECT 1
                    FROM dbo.Talla AS T
                    WHERE (T.IdTalla = TA.IdTalla)
                )
            )
            OR (
                SELECT COUNT(DISTINCT TA.IdTalla)
                FROM @tallas AS TA
            ) <> (
                SELECT COUNT(1)
                FROM @tallas
            )
        BEGIN
            SET @outResultCode = 50010; -- lista de tallas inválida
            RETURN;
        END;

        -- GI002 restricción 1: cantidad entera y no negativa
        IF EXISTS (
            SELECT 1
            FROM @tallas AS TA
            WHERE (TA.Cantidad IS NULL)
                OR (TA.Cantidad < 0)
        )
        BEGIN
            SET @outResultCode = 50009; -- cantidad inválida
            RETURN;
        END;

        -- variables para la transacción
        DECLARE @idProducto INT
            , @jsonDespues NVARCHAR(MAX);

        -- transacción: producto, tallas y bitácora se guardan juntos o nada
        BEGIN TRANSACTION tAgregarProducto;

            INSERT INTO dbo.Producto (
                IdCategoria
                , Nombre
                , Descripcion
                , Precio
            )
            VALUES (
                @inIdCategoria
                , @nombre
                , @descripcion
                , @inPrecio
            );

            SET @idProducto = SCOPE_IDENTITY();

            INSERT INTO dbo.ProductoTalla (
                IdProducto
                , IdTalla
                , Cantidad
            )
            SELECT @idProducto
                , TA.IdTalla
                , TA.Cantidad
            FROM @tallas AS TA;

            -- el JSON se arma después de insertar para que lleve el Id y las tallas
            SET @jsonDespues = dbo.fnJsonProducto(@idProducto);

            INSERT INTO dbo.Bitacora (
                IdUsuario
                , IdTipoOperacion
                , IP
                , DatosAntes
                , DatosDespues
            )
            VALUES (
                @inIdUsuario
                , @tipoOperacionAgregar
                , @inIP
                , NULL
                , @jsonDespues
            );

        COMMIT TRANSACTION tAgregarProducto;

        -- resultado para la capa lógica: con este Id se sube la foto
        SELECT @idProducto AS IdProducto;

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
