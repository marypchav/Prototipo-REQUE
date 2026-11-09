CREATE OR ALTER PROCEDURE dbo.spConfirmarOrden
    @inIdUsuario INT -- cliente que confirma
    , @inIP VARCHAR(64) -- ip del cliente, para la bitácora
    , @inIdMetodoPago INT -- SINPE Móvil o efectivo (GP011)
    , @inIdMetodoEntrega INT -- método de entrega (GP012)
    , @inIdDireccion INT -- dirección guardada; NULL si es retiro en el taller
    , @inRutaComprobante VARCHAR(260) -- imagen del comprobante SINPE; NULL si es efectivo
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP014 Confirmar orden de compra (incluye GP011, GP012, GP013 y GP020).
Es el SP más importante del proyecto: aquí se cumplen las propiedades ACID
que pide la ERS (sección 2.4 y acuerdo 2 de la minuta #1).

Cómo se evita vender dos veces una pieza única:
    Dentro de la transacción se leen las existencias de los productos del
    carrito con WITH (UPDLOCK, HOLDLOCK). Ese bloqueo dura hasta el COMMIT.
    Si otro cliente confirma al mismo tiempo una orden con la misma talla,
    su SP se queda esperando en esa lectura; cuando el primero termina, el
    segundo ve las existencias ya descontadas y recibe 50016.
    Resultado: se vende al primero que confirma (minuta #1, tema 2).

Si algún producto ya no está disponible no se registra nada (ni pedido ni
descuento) y se devuelve la lista de productos que fallaron (flujo
alternativo de GP014).

Resultado si todo sale bien: número de pedido y montos.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spConfirmarOrden
        @inIdUsuario = 2
        , @inIP = '127.0.0.1'
        , @inIdMetodoPago = 1
        , @inIdMetodoEntrega = 1
        , @inIdDireccion = 1
        , @inRutaComprobante = 'uploads/comprobantes/2_1731190000.jpg'
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0
            , @estadoPendiente INT = 1 -- "Pendiente de confirmación"
            , @tipoOperacionConfirmar INT = 10; -- "Confirmar orden de compra"

        -- variables de uso general
        DECLARE @requiereComprobante BIT
            , @soloRetiro BIT
            , @requiereDireccion BIT
            , @costoEnvio MONEY
            , @direccionTexto NVARCHAR(400)
            , @rutaComprobante VARCHAR(260);

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @requiereComprobante = NULL; -- NULL = método de pago no existe
        SET @requiereDireccion = NULL; -- NULL = método de entrega no existe
        SET @direccionTexto = NULL;
        SET @rutaComprobante = LOWER(NULLIF(LTRIM(RTRIM(@inRutaComprobante)), ''));

        -- validaciones
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Usuario AS U
            WHERE (U.IdUsuario = @inIdUsuario)
                AND (U.FlagActivo = @true)
        )
        BEGIN
            SET @outResultCode = 50001; -- usuario no existe
            RETURN;
        END;

        -- GP014 precondición 2: carrito con al menos un producto
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.CarritoDetalle AS CD
            WHERE (CD.IdUsuario = @inIdUsuario)
        )
        BEGIN
            SET @outResultCode = 50017; -- carrito vacío
            RETURN;
        END;

        -- método de pago
        SELECT @requiereComprobante = MP.FlagRequiereComprobante
            , @soloRetiro = MP.FlagSoloRetiro
        FROM dbo.MetodoPago AS MP
        WHERE (MP.IdMetodoPago = @inIdMetodoPago);

        IF (@requiereComprobante IS NULL)
        BEGIN
            SET @outResultCode = 50019; -- método de pago no existe
            RETURN;
        END;

        -- método de entrega
        SELECT @requiereDireccion = ME.FlagRequiereDireccion
            , @costoEnvio = ME.CostoEnvio
        FROM dbo.MetodoEntrega AS ME
        WHERE (ME.IdMetodoEntrega = @inIdMetodoEntrega);

        IF (@requiereDireccion IS NULL)
        BEGIN
            SET @outResultCode = 50020; -- método de entrega no existe
            RETURN;
        END;

        -- GP011 restricción 2: efectivo solo con retiro en el taller
        IF (@soloRetiro = @true)
            AND (@requiereDireccion = @true)
        BEGIN
            SET @outResultCode = 50021; -- efectivo solo para retiro en el taller
            RETURN;
        END;

        -- GP012 restricción 2: los métodos con envío necesitan una dirección
        -- activa del propio cliente. Se copia como texto al pedido
        IF (@requiereDireccion = @true)
        BEGIN
            SELECT @direccionTexto = CONCAT(
                    D.OtrasSenas, N', ', D.Distrito, N', ', D.Canton, N', ', PR.Nombre
                )
            FROM dbo.Direccion AS D
            INNER JOIN dbo.Provincia AS PR
                ON (PR.IdProvincia = D.IdProvincia)
            WHERE (D.IdDireccion = @inIdDireccion)
                AND (D.IdUsuario = @inIdUsuario)
                AND (D.FlagActivo = @true);

            IF (@direccionTexto IS NULL)
            BEGIN
                SET @outResultCode = 50022; -- falta una dirección válida
                RETURN;
            END;
        END;

        -- GP013 restricción 2: SINPE requiere comprobante
        IF (@requiereComprobante = @true)
            AND (@rutaComprobante IS NULL)
        BEGIN
            SET @outResultCode = 50023; -- falta el comprobante
            RETURN;
        END;

        -- GP013 restricción 1: png o jpg
        IF (@requiereComprobante = @true)
            AND (@rutaComprobante NOT LIKE '%.png')
            AND (@rutaComprobante NOT LIKE '%.jpg')
            AND (@rutaComprobante NOT LIKE '%.jpeg')
        BEGIN
            SET @outResultCode = 50012; -- formato de imagen no permitido
            RETURN;
        END;

        -- si paga en efectivo no se guarda comprobante aunque venga uno
        SET @rutaComprobante = CASE
                WHEN (@requiereComprobante = @true) THEN @rutaComprobante
                ELSE NULL
            END;

        -- variables para la transacción
        DECLARE @cantidadLineas INT
            , @subtotal MONEY
            , @total MONEY
            , @idPedido INT
            , @jsonDespues NVARCHAR(MAX);

        -- productos del carrito que ya no se pueden vender
        DECLARE @noDisponibles TABLE (
            IdCarritoDetalle INT NOT NULL
            , NombreProducto NVARCHAR(100) NOT NULL
            , Talla NVARCHAR(16) NOT NULL
            , CantidadSolicitada INT NOT NULL
            , CantidadDisponible INT NOT NULL
        );

        -- transacción: verificar existencias, descontarlas, crear el pedido,
        -- guardar el comprobante y vaciar el carrito es UNA sola operación
        BEGIN TRANSACTION tConfirmarOrden;

            -- 1. bloquea las existencias de todo lo que hay en el carrito.
            -- UPDLOCK: nadie más puede tomar estas filas para modificarlas.
            -- HOLDLOCK: el bloqueo se mantiene hasta el COMMIT o ROLLBACK
            SELECT @cantidadLineas = COUNT(1)
            FROM dbo.CarritoDetalle AS CD
            INNER JOIN dbo.ProductoTalla AS PT WITH (UPDLOCK, HOLDLOCK)
                ON (PT.IdProductoTalla = CD.IdProductoTalla)
            WHERE (CD.IdUsuario = @inIdUsuario);

            -- 2. con las filas bloqueadas, revisa qué ya no está disponible
            -- (producto eliminado o existencias menores a lo pedido)
            INSERT INTO @noDisponibles (
                IdCarritoDetalle
                , NombreProducto
                , Talla
                , CantidadSolicitada
                , CantidadDisponible
            )
            SELECT CD.IdCarritoDetalle
                , P.Nombre
                , T.Nombre
                , CD.Cantidad
                , CASE
                    WHEN (P.FlagActivo = @true) THEN PT.Cantidad
                    ELSE 0
                  END
            FROM dbo.CarritoDetalle AS CD
            INNER JOIN dbo.ProductoTalla AS PT
                ON (PT.IdProductoTalla = CD.IdProductoTalla)
            INNER JOIN dbo.Producto AS P
                ON (P.IdProducto = PT.IdProducto)
            INNER JOIN dbo.Talla AS T
                ON (T.IdTalla = PT.IdTalla)
            WHERE (CD.IdUsuario = @inIdUsuario)
                AND (
                    (P.FlagActivo = @false)
                    OR (PT.Cantidad < CD.Cantidad)
                );

            -- si algo falló no se registra nada: se deshace y se informa cuáles
            IF EXISTS (
                SELECT 1
                FROM @noDisponibles
            )
            BEGIN
                ROLLBACK TRANSACTION tConfirmarOrden;

                -- la variable tabla no se pierde con el ROLLBACK
                SELECT ND.IdCarritoDetalle
                    , ND.NombreProducto
                    , ND.Talla
                    , ND.CantidadSolicitada
                    , ND.CantidadDisponible
                FROM @noDisponibles AS ND;

                SET @outResultCode = 50016; -- existencias insuficientes
                RETURN;
            END;

            -- 3. montos con el precio vigente (GP020)
            SELECT @subtotal = SUM(P.Precio * CD.Cantidad)
            FROM dbo.CarritoDetalle AS CD
            INNER JOIN dbo.ProductoTalla AS PT
                ON (PT.IdProductoTalla = CD.IdProductoTalla)
            INNER JOIN dbo.Producto AS P
                ON (P.IdProducto = PT.IdProducto)
            WHERE (CD.IdUsuario = @inIdUsuario);

            SET @total = @subtotal + ISNULL(@costoEnvio, 0); -- NULL = envío a coordinar

            -- 4. el pedido. El trigger trPedidoPrimerEstado agrega su primer
            -- registro en HistorialEstadoPedido
            INSERT INTO dbo.Pedido (
                IdUsuario
                , IdEstadoPedido
                , IdMetodoPago
                , IdMetodoEntrega
                , DireccionEntrega
                , SubtotalProductos
                , CostoEnvio
                , Total
            )
            VALUES (
                @inIdUsuario
                , @estadoPendiente
                , @inIdMetodoPago
                , @inIdMetodoEntrega
                , @direccionTexto
                , @subtotal
                , @costoEnvio
                , @total
            );

            -- SCOPE_IDENTITY (y no @@IDENTITY) para no tomar el id que
            -- generó el trigger en HistorialEstadoPedido
            SET @idPedido = SCOPE_IDENTITY();

            -- 5. detalle con copia de nombre, talla y precio (sección 2.4)
            INSERT INTO dbo.PedidoDetalle (
                IdPedido
                , IdProductoTalla
                , NombreProducto
                , NombreTalla
                , PrecioUnitario
                , Cantidad
                , Subtotal
            )
            SELECT @idPedido
                , CD.IdProductoTalla
                , P.Nombre
                , T.Nombre
                , P.Precio
                , CD.Cantidad
                , P.Precio * CD.Cantidad
            FROM dbo.CarritoDetalle AS CD
            INNER JOIN dbo.ProductoTalla AS PT
                ON (PT.IdProductoTalla = CD.IdProductoTalla)
            INNER JOIN dbo.Producto AS P
                ON (P.IdProducto = PT.IdProducto)
            INNER JOIN dbo.Talla AS T
                ON (T.IdTalla = PT.IdTalla)
            WHERE (CD.IdUsuario = @inIdUsuario);

            -- 6. descuenta las existencias (GP014 postcondición 2)
            UPDATE PT
            SET Cantidad = PT.Cantidad - CD.Cantidad
            FROM dbo.ProductoTalla AS PT
            INNER JOIN dbo.CarritoDetalle AS CD
                ON (CD.IdProductoTalla = PT.IdProductoTalla)
            WHERE (CD.IdUsuario = @inIdUsuario);

            -- 7. comprobante, solo si es SINPE. Sin IF: el WHERE decide
            INSERT INTO dbo.Comprobante (
                IdPedido
                , RutaArchivo
            )
            SELECT @idPedido
                , @rutaComprobante
            WHERE (@rutaComprobante IS NOT NULL);

            -- 8. vacía el carrito (GP014 paso 2.4)
            DELETE FROM dbo.CarritoDetalle
            WHERE (IdUsuario = @inIdUsuario);

            -- 9. bitácora con el pedido completo
            SET @jsonDespues = (
                SELECT P.IdPedido
                    , MP.Nombre AS MetodoPago
                    , ME.Nombre AS MetodoEntrega
                    , P.DireccionEntrega
                    , P.SubtotalProductos
                    , P.CostoEnvio
                    , P.Total
                    , (
                        SELECT PD.NombreProducto
                            , PD.NombreTalla
                            , PD.Cantidad
                            , PD.PrecioUnitario
                        FROM dbo.PedidoDetalle AS PD
                        WHERE (PD.IdPedido = P.IdPedido)
                        FOR JSON PATH
                      ) AS Productos
                FROM dbo.Pedido AS P
                INNER JOIN dbo.MetodoPago AS MP
                    ON (MP.IdMetodoPago = P.IdMetodoPago)
                INNER JOIN dbo.MetodoEntrega AS ME
                    ON (ME.IdMetodoEntrega = P.IdMetodoEntrega)
                WHERE (P.IdPedido = @idPedido)
                FOR JSON PATH, INCLUDE_NULL_VALUES, WITHOUT_ARRAY_WRAPPER
            );

            INSERT INTO dbo.Bitacora (
                IdUsuario
                , IdTipoOperacion
                , IP
                , DatosAntes
                , DatosDespues
            )
            VALUES (
                @inIdUsuario
                , @tipoOperacionConfirmar
                , @inIP
                , NULL
                , @jsonDespues
            );

        COMMIT TRANSACTION tConfirmarOrden;

        -- resultado para la capa lógica (GP014 criterio 3: número de pedido)
        SELECT @idPedido AS IdPedido
            , @subtotal AS SubtotalProductos
            , @costoEnvio AS CostoEnvio
            , @total AS Total;

    END TRY
    BEGIN CATCH

        -- si quedó una transacción abierta, se deshace todo
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
