CREATE OR ALTER PROCEDURE dbo.spObtenerPedido
    @inIdUsuario INT -- quién consulta
    , @inIdPedido INT -- pedido que se consulta
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP015 Visualizar comprobantes por administrador (detalle) y detalle de
GP018 Consultar historial de pedido. Solo la administradora o el dueño.

Devuelve cuatro resultados:
    1. encabezado del pedido, con la ruta del comprobante (NULL si es efectivo)
    2. productos
    3. historial de estados
    4. estados a los que puede pasar (solo para la administradora; vacío
       para el cliente). Sirve para GP017 paso 2.1

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
            , @idDueno INT
            , @idEstadoActual INT
            , @requiereDireccion BIT;

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @esAdministrador = @false;
        SET @idDueno = NULL;

        -- validaciones
        SELECT @idDueno = P.IdUsuario
            , @idEstadoActual = P.IdEstadoPedido
            , @requiereDireccion = ME.FlagRequiereDireccion
        FROM dbo.Pedido AS P
        INNER JOIN dbo.MetodoEntrega AS ME
            ON (ME.IdMetodoEntrega = P.IdMetodoEntrega)
        WHERE (P.IdPedido = @inIdPedido);

        SELECT @esAdministrador = U.EsAdministrador
        FROM dbo.Usuario AS U
        WHERE (U.IdUsuario = @inIdUsuario)
            AND (U.FlagActivo = @true);

        -- mismo código si no existe o si es de otro cliente: no se revela
        -- que existe un pedido ajeno
        IF (@idDueno IS NULL)
            OR (
                (@esAdministrador = @false)
                AND (@idDueno <> @inIdUsuario)
            )
        BEGIN
            SET @outResultCode = 50024; -- pedido no existe o sin acceso
            RETURN;
        END;

        -- primer resultado: encabezado
        SELECT P.IdPedido
            , P.FechaCreacion
            , U.Nombre AS Cliente
            , U.Correo
            , U.Telefono
            , P.IdEstadoPedido
            , EP.Nombre AS Estado
            , P.MotivoEstado
            , MP.Nombre AS MetodoPago
            , MP.FlagRequiereComprobante
            , ME.Nombre AS MetodoEntrega
            , ME.FlagRequiereDireccion
            , P.DireccionEntrega
            , P.SubtotalProductos
            , P.CostoEnvio
            , P.Total
            , CO.RutaArchivo AS RutaComprobante -- NULL = efectivo (GP015 alterno)
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

        -- segundo resultado: productos (copia del momento de la compra)
        SELECT PD.IdPedidoDetalle
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

        -- tercer resultado: historial de estados
        SELECT HEP.FechaHora
            , EP.Nombre AS Estado
            , HEP.Comentario
        FROM dbo.HistorialEstadoPedido AS HEP
        INNER JOIN dbo.EstadoPedido AS EP
            ON (EP.IdEstadoPedido = HEP.IdEstadoPedido)
        WHERE (HEP.IdPedido = @inIdPedido)
        ORDER BY HEP.FechaHora
            , HEP.IdHistorialEstadoPedido;

        -- cuarto resultado: siguientes estados permitidos, según el estado
        -- actual y si el pedido es con envío o con retiro
        SELECT EP.IdEstadoPedido
            , EP.Nombre
            , EP.FlagRequiereMotivo
        FROM dbo.TransicionEstadoPedido AS TEP
        INNER JOIN dbo.EstadoPedido AS EP
            ON (EP.IdEstadoPedido = TEP.IdEstadoNuevo)
        WHERE (@esAdministrador = @true)
            AND (TEP.IdEstadoActual = @idEstadoActual)
            AND (
                (TEP.FlagSoloEnvio = @false)
                OR (@requiereDireccion = @true)
            )
            AND (
                (TEP.FlagSoloRetiro = @false)
                OR (@requiereDireccion = @false)
            )
        ORDER BY EP.IdEstadoPedido;

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
