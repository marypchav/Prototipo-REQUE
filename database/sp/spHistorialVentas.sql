CREATE OR ALTER PROCEDURE dbo.spHistorialVentas
    @inIdUsuario INT -- quién consulta, debe ser administradora
    , @inFechaInicio DATE -- desde (NULL = sin límite)
    , @inFechaFin DATE -- hasta, inclusive (NULL = sin límite)
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GI009 Historial de productos vendidos.
Cuenta como venta todo pedido que la administradora ya confirmó y que no
terminó rechazado ni cancelado (criterio 1: "órdenes completadas").
Es solo lectura: no hay SP para modificar ni borrar este historial
(restricción 2), porque sale de PedidoDetalle, que nunca se edita.

Devuelve dos resultados:
    1. detalle de productos vendidos
    2. resumen: cantidad de prendas y monto total

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spHistorialVentas
        @inIdUsuario = 1
        , @inFechaInicio = NULL
        , @inFechaFin = NULL
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0
            , @estadoPendiente INT = 1;

        -- variables de uso general
        DECLARE @esAdministrador BIT
            , @fechaFinExclusiva DATE;

        -- ventas que cumplen los filtros
        DECLARE @ventas TABLE (
            IdPedidoDetalle INT NOT NULL PRIMARY KEY
        );

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @esAdministrador = @false;
        -- FechaCreacion tiene hora: se compara contra el día siguiente
        SET @fechaFinExclusiva = DATEADD(DAY, 1, @inFechaFin);

        -- validaciones: restricción 1, solo administración
        SELECT @esAdministrador = U.EsAdministrador
        FROM dbo.Usuario AS U
        WHERE (U.IdUsuario = @inIdUsuario)
            AND (U.FlagActivo = @true);

        IF (@esAdministrador = @false)
        BEGIN
            SET @outResultCode = 50002; -- requiere rol de administración
            RETURN;
        END;

        -- preprocesamiento
        INSERT INTO @ventas (
            IdPedidoDetalle
        )
        SELECT PD.IdPedidoDetalle
        FROM dbo.PedidoDetalle AS PD
        INNER JOIN dbo.Pedido AS P
            ON (P.IdPedido = PD.IdPedido)
        INNER JOIN dbo.EstadoPedido AS EP
            ON (EP.IdEstadoPedido = P.IdEstadoPedido)
        WHERE (P.IdEstadoPedido <> @estadoPendiente)
            AND (EP.FlagDevuelveInventario = @false) -- excluye rechazados y cancelados
            AND (
                (@inFechaInicio IS NULL)
                OR (P.FechaCreacion >= @inFechaInicio)
            )
            AND (
                (@inFechaFin IS NULL)
                OR (P.FechaCreacion < @fechaFinExclusiva)
            );

        -- primer resultado: detalle
        SELECT P.IdPedido
            , P.FechaCreacion
            , U.Nombre AS Cliente
            , PD.NombreProducto
            , PD.NombreTalla
            , PD.Cantidad
            , PD.PrecioUnitario
            , PD.Subtotal
            , EP.Nombre AS Estado
        FROM @ventas AS V
        INNER JOIN dbo.PedidoDetalle AS PD
            ON (PD.IdPedidoDetalle = V.IdPedidoDetalle)
        INNER JOIN dbo.Pedido AS P
            ON (P.IdPedido = PD.IdPedido)
        INNER JOIN dbo.Usuario AS U
            ON (U.IdUsuario = P.IdUsuario)
        INNER JOIN dbo.EstadoPedido AS EP
            ON (EP.IdEstadoPedido = P.IdEstadoPedido)
        ORDER BY P.FechaCreacion DESC
            , PD.IdPedidoDetalle;

        -- segundo resultado: resumen
        SELECT ISNULL(SUM(PD.Cantidad), 0) AS PrendasVendidas
            , ISNULL(SUM(PD.Subtotal), 0) AS MontoVendido
        FROM @ventas AS V
        INNER JOIN dbo.PedidoDetalle AS PD
            ON (PD.IdPedidoDetalle = V.IdPedidoDetalle);

    END TRY
    BEGIN CATCH

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
