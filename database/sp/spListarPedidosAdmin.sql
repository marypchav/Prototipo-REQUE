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
