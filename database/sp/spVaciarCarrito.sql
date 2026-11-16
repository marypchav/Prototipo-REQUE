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
