CREATE OR ALTER PROCEDURE dbo.spEliminarDireccion
    @inIdUsuario INT -- cliente que elimina (debe ser el dueño)
    , @inIP VARCHAR(64) -- ip del cliente, para la bitácora
    , @inIdDireccion INT -- dirección que se elimina
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP006 Eliminar dirección de envío.
Eliminación lógica: deja de mostrarse y de ofrecerse al elegir el método
de entrega (criterio 2). La confirmación la hace el frontend.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spEliminarDireccion
        @inIdUsuario = 2
        , @inIP = '127.0.0.1'
        , @inIdDireccion = 1
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0
            , @tipoOperacionEliminar INT = 9; -- TipoOperacion "Eliminar dirección"

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito

        -- validaciones: debe existir, estar activa y ser del cliente
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Direccion AS D
            WHERE (D.IdDireccion = @inIdDireccion)
                AND (D.IdUsuario = @inIdUsuario)
                AND (D.FlagActivo = @true)
        )
        BEGIN
            SET @outResultCode = 50014; -- dirección no existe o no es del cliente
            RETURN;
        END;

        -- variables para el preprocesamiento y la transacción
        DECLARE @jsonAntes NVARCHAR(MAX)
            , @jsonDespues NVARCHAR(MAX);

        -- preprocesamiento
        SET @jsonAntes = dbo.fnJsonDireccion(@inIdDireccion);

        -- transacción: eliminación lógica y bitácora van juntas
        BEGIN TRANSACTION tEliminarDireccion;

            UPDATE dbo.Direccion
            SET FlagActivo = @false
            WHERE (IdDireccion = @inIdDireccion);

            SET @jsonDespues = dbo.fnJsonDireccion(@inIdDireccion);

            INSERT INTO dbo.Bitacora (
                IdUsuario
                , IdTipoOperacion
                , IP
                , DatosAntes
                , DatosDespues
            )
            VALUES (
                @inIdUsuario
                , @tipoOperacionEliminar
                , @inIP
                , @jsonAntes
                , @jsonDespues
            );

        COMMIT TRANSACTION tEliminarDireccion;

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
