CREATE OR ALTER PROCEDURE dbo.spObtenerPedido
    @inIdUsuario INT -- usuario con sesión iniciada (cliente o administradora)
    , @inIdPedido INT -- pedido que se consulta
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
Detalle de un pedido. Lo usan dos requerimientos:
  - GP015 paso 4.1 (administradora): detalle + comprobante.
  - GP018 paso 4.1 (cliente): solo si el pedido es suyo (restricción 1).
El SP revisa en la tabla Usuario si quien pide es administradora; si es
cliente y el pedido no es suyo, responde "no existe" (no revela nada).

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spObtenerPedido
        @inIdUsuario = 1
        , @inIdPedido = 1
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0;

        -- variables de uso general
        DECLARE @esAdministrador BIT
            , @requiereDireccion BIT
            , @estadoActual INT;

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito

        SELECT @esAdministrador = U.EsAdministrador
        FROM dbo.Usuario AS U
        WHERE (U.IdUsuario = @inIdUsuario)
            AND (U.FlagActivo = @true);

        -- validaciones
        IF (@esAdministrador IS NULL)
            OR NOT EXISTS (
                SELECT 1
                FROM dbo.Pedido AS P
                WHERE (P.IdPedido = @inIdPedido)
                    AND (
                        (@esAdministrador = @true)
                        OR (P.IdUsuario = @inIdUsuario)
                    )
            )
        BEGIN
            SET @outResultCode = 50056; -- el pedido no existe
            RETURN;
        END;

        SELECT @estadoActual = P.IdEstadoPedido
            , @requiereDireccion = ME.FlagRequiereDireccion
        FROM dbo.Pedido AS P
        INNER JOIN dbo.MetodoEntrega AS ME
            ON (ME.IdMetodoEntrega = P.IdMetodoEntrega)
        WHERE (P.IdPedido = @inIdPedido);

        -- primer resultado: encabezado (GP015 restricción 2).
        -- RutaComprobante NULL y pago en efectivo = "Pago en efectivo al retirar en el taller"
        SELECT P.IdPedido
            , P.FechaCreacion
            , P.IdEstadoPedido
            , EP.Nombre AS Estado
            , P.MotivoEstado
            , U.IdUsuario AS IdCliente
            , U.Nombre AS Cliente
            , U.Correo
            , U.Telefono
            , MP.Nombre AS MetodoPago
            , MP.FlagRequiereComprobante
            , ME.Nombre AS MetodoEntrega
            , ME.FlagRequiereDireccion
            , P.DireccionEntrega
            , P.SubtotalProductos
            , P.CostoEnvio -- NULL = envío a coordinar
            , P.Total
            , CO.RutaArchivo AS RutaComprobante
            , CO.FechaSubida AS FechaComprobante
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
        WHERE (P.IdPedido = @inIdPedido);

        -- segundo resultado: productos, con los datos guardados al comprar
        SELECT PD.IdPedidoDetalle
            , PD.IdProductoTalla
            , PT.IdProducto
            , PD.NombreProducto
            , PD.NombreTalla
            , PD.PrecioUnitario
            , PD.Cantidad
            , PD.Subtotal
            , PR.RutaImagen
        FROM dbo.PedidoDetalle AS PD
        INNER JOIN dbo.ProductoTalla AS PT
            ON (PT.IdProductoTalla = PD.IdProductoTalla)
        INNER JOIN dbo.Producto AS PR
            ON (PR.IdProducto = PT.IdProducto)
        WHERE (PD.IdPedido = @inIdPedido)
        ORDER BY PD.IdPedidoDetalle;

        -- tercer resultado: historial de estados con fecha, hora y motivo
        -- (GP016 paso 2.1, GP017 paso 4.1, GP019 restricción 2)
        SELECT H.FechaHora
            , H.IdEstadoPedido
            , EP.Nombre AS Estado
            , H.Comentario
        FROM dbo.HistorialEstadoPedido AS H
        INNER JOIN dbo.EstadoPedido AS EP
            ON (EP.IdEstadoPedido = H.IdEstadoPedido)
        WHERE (H.IdPedido = @inIdPedido)
        ORDER BY H.FechaHora
            , H.IdHistorialEstadoPedido;

        -- cuarto resultado: estados a los que puede pasar según el estado actual
        -- y el método de entrega (GP017 paso 2.1). Vacío para clientes
        SELECT TE.IdEstadoNuevo AS IdEstadoPedido
            , EP.Nombre
            , EP.FlagRequiereMotivo -- pedir motivo (Rechazado)
            , EP.FlagDevuelveInventario -- pedir confirmación (Cancelado)
        FROM dbo.TransicionEstadoPedido AS TE
        INNER JOIN dbo.EstadoPedido AS EP
            ON (EP.IdEstadoPedido = TE.IdEstadoNuevo)
        WHERE (@esAdministrador = @true)
            AND (TE.IdEstadoActual = @estadoActual)
            AND (
                (TE.FlagSoloEnvio = @false)
                OR (@requiereDireccion = @true)
            )
            AND (
                (TE.FlagSoloRetiro = @false)
                OR (@requiereDireccion = @false)
            )
        ORDER BY TE.IdEstadoNuevo;

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
