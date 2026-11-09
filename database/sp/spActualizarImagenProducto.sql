CREATE OR ALTER PROCEDURE dbo.spActualizarImagenProducto
    @inIdUsuario INT -- quién sube la foto, debe ser administradora
    , @inIP VARCHAR(64) -- ip del cliente, para la bitácora
    , @inIdProducto INT -- producto al que se asigna la foto
    , @inRutaImagen VARCHAR(260) -- ruta donde Node guardó el archivo
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GI003 Subir foto del producto.
Node recibe el archivo, valida tamaño, lo guarda en disco y llama este SP
con la ruta. Aquí se valida otra vez la extensión (png o jpg).
Se devuelve la ruta anterior para que Node borre el archivo viejo.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spActualizarImagenProducto
        @inIdUsuario = 1
        , @inIP = '127.0.0.1'
        , @inIdProducto = 1
        , @inRutaImagen = 'uploads/productos/1_1731190000.jpg'
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0
            , @tipoOperacionFoto INT = 6; -- TipoOperacion "Subir foto de producto"

        -- variables de uso general
        DECLARE @esAdministrador BIT
            , @ruta VARCHAR(260)
            , @rutaAnterior VARCHAR(260);

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @esAdministrador = @false;
        SET @ruta = LOWER(LTRIM(RTRIM(ISNULL(@inRutaImagen, ''))));

        -- validaciones
        SELECT @esAdministrador = U.EsAdministrador
        FROM dbo.Usuario AS U
        WHERE (U.IdUsuario = @inIdUsuario)
            AND (U.FlagActivo = @true);

        IF (@esAdministrador = @false)
        BEGIN
            SET @outResultCode = 50002; -- requiere rol de administración
            RETURN;
        END;

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

        -- GI003 restricción 1: solo png o jpg
        IF (@ruta NOT LIKE '%.png')
            AND (@ruta NOT LIKE '%.jpg')
            AND (@ruta NOT LIKE '%.jpeg')
        BEGIN
            SET @outResultCode = 50012; -- formato de imagen no permitido
            RETURN;
        END;

        -- variables para el preprocesamiento y la transacción
        DECLARE @jsonAntes NVARCHAR(MAX)
            , @jsonDespues NVARCHAR(MAX);

        -- preprocesamiento
        SELECT @rutaAnterior = P.RutaImagen
        FROM dbo.Producto AS P
        WHERE (P.IdProducto = @inIdProducto);

        SET @jsonAntes = dbo.fnJsonProducto(@inIdProducto);

        -- transacción: foto y bitácora van juntas
        BEGIN TRANSACTION tActualizarImagenProducto;

            UPDATE dbo.Producto
            SET RutaImagen = @ruta
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
                , @tipoOperacionFoto
                , @inIP
                , @jsonAntes
                , @jsonDespues
            );

        COMMIT TRANSACTION tActualizarImagenProducto;

        -- resultado para la capa lógica: archivo viejo que puede borrar
        SELECT @rutaAnterior AS RutaAnterior;

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
