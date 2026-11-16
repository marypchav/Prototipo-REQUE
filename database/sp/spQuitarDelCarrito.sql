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
