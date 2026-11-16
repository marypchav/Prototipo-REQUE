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
