CREATE OR ALTER PROCEDURE dbo.spActualizarImagenProducto
    @inIdProducto INT -- producto al que se le asigna la foto
    , @inRutaImagen NVARCHAR(260) -- ruta que guardó el backend: uploads/productos/archivo.jpg
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GI003 Subir foto del producto. El backend recibe el archivo, revisa que sea
png o jpg, lo guarda en uploads/productos y llama este SP con la ruta.
Devuelve la ruta anterior para que el backend borre la foto vieja.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spActualizarImagenProducto
        @inIdProducto = 1
        , @inRutaImagen = N'uploads/productos/1-1731600000000.jpg'
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1;

        -- variables de uso general
        DECLARE @rutaImagen NVARCHAR(260)
            , @rutaAnterior NVARCHAR(260);

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @rutaImagen = NULLIF(LTRIM(RTRIM(@inRutaImagen)), N'');

        -- validaciones
        -- GI003 restricción 1: solo png o jpg
        IF (@rutaImagen IS NULL)
            OR (
                (LOWER(@rutaImagen) NOT LIKE N'%.png')
                AND (LOWER(@rutaImagen) NOT LIKE N'%.jpg')
                AND (LOWER(@rutaImagen) NOT LIKE N'%.jpeg')
            )
        BEGIN
            SET @outResultCode = 50027; -- formato de imagen no permitido
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

        BEGIN TRANSACTION tActualizarImagen;

            -- lee y bloquea la fila para que nadie la cambie entre la lectura y el UPDATE
            SELECT @rutaAnterior = P.RutaImagen
            FROM dbo.Producto AS P WITH (UPDLOCK, HOLDLOCK)
            WHERE (P.IdProducto = @inIdProducto);

            UPDATE dbo.Producto
            SET RutaImagen = @rutaImagen
            WHERE (IdProducto = @inIdProducto);

        COMMIT TRANSACTION tActualizarImagen;

        -- primer resultado: foto anterior (NULL si no tenía)
        SELECT @rutaAnterior AS RutaImagenAnterior;

    END TRY
    BEGIN CATCH

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
