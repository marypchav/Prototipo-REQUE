CREATE OR ALTER PROCEDURE dbo.spConfirmarOrden
    @inIdUsuario INT -- cliente con sesión iniciada
    , @inIdMetodoPago INT -- GP011
    , @inIdMetodoEntrega INT -- GP012
    , @inIdDireccion INT -- GP012: obligatoria si la entrega es con envío; se ignora en retiro
    , @inRutaComprobante NVARCHAR(260) -- GP013: uploads/comprobantes/archivo.jpg (NULL si no aplica)
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP014 Confirmar orden de compra (incluye lo elegido en GP011, GP012 y GP013).

GP014 restricción 1 (ACID): todo pasa en UNA transacción. Las filas de
ProductoTalla del carrito se bloquean (UPDLOCK, HOLDLOCK) antes de revisar
las existencias, así si dos clientes piden el mismo producto único, el
segundo espera a que el primero termine y luego ve que ya no hay: se vende
al primero que confirma (criterio 2).

Flujo alterno 1: si algún producto ya no alcanza, no se registra la orden ni
se descuenta nada, y se devuelven las líneas que fallaron (código 50055 + datos).
Flujo alterno 2: si falta un dato (pago, entrega, dirección o comprobante),
se indica cuál con su propio código.

El comprobante: el backend guarda primero el archivo (png/jpg, máx. 5 MB,
GP013 restricción 1) y manda la ruta. Si este SP devuelve error, el backend
borra ese archivo.

El monto final queda guardado en la orden (GP020 postcondición 2).
CostoEnvio NULL = envío a coordinar; el total incluye solo los productos.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spConfirmarOrden
        @inIdUsuario = 2
        , @inIdMetodoPago = 1
        , @inIdMetodoEntrega = 1
        , @inIdDireccion = 1
        , @inRutaComprobante = N'uploads/comprobantes/2-1731600000000.jpg'
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0
            , @estadoPendiente INT = 1; -- "Pendiente de confirmación" (GP014 restricción 2)

        -- variables de uso general
        DECLARE @requiereComprobante BIT
            , @soloRetiro BIT
            , @requiereDireccion BIT
            , @costoEnvio MONEY
            , @direccionTexto NVARCHAR(400)
            , @rutaComprobante NVARCHAR(260)
            , @subtotalProductos MONEY
            , @total MONEY
            , @idPedido INT;

        -- líneas del carrito, leídas con bloqueo dentro de la transacción
        DECLARE @lineas TABLE (
            IdCarritoDetalle INT NOT NULL PRIMARY KEY
            , IdProductoTalla INT NOT NULL
            , IdProducto INT NOT NULL
            , NombreProducto NVARCHAR(100) NOT NULL
            , NombreTalla NVARCHAR(16) NOT NULL
            , PrecioUnitario MONEY NOT NULL
            , Cantidad INT NOT NULL
            , Existencias INT NOT NULL
            , FlagActivo BIT NOT NULL
        );

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @rutaComprobante = NULLIF(LTRIM(RTRIM(@inRutaComprobante)), N'');

        -- validaciones (GP014 paso 2.1: la información debe estar completa)
        -- GP014 precondición 2: carrito con al menos un producto
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.CarritoDetalle AS CD
            WHERE (CD.IdUsuario = @inIdUsuario)
        )
        BEGIN
            SET @outResultCode = 50050; -- el carrito está vacío
            RETURN;
        END;

        SELECT @requiereComprobante = MP.FlagRequiereComprobante
            , @soloRetiro = MP.FlagSoloRetiro
        FROM dbo.MetodoPago AS MP
        WHERE (MP.IdMetodoPago = @inIdMetodoPago);

        SELECT @requiereDireccion = ME.FlagRequiereDireccion
            , @costoEnvio = ME.CostoEnvio
        FROM dbo.MetodoEntrega AS ME
        WHERE (ME.IdMetodoEntrega = @inIdMetodoEntrega);

        -- GP011 criterio 1 / GP012: un método de pago y uno de entrega válidos
        IF (@requiereComprobante IS NULL)
            OR (@requiereDireccion IS NULL)
        BEGIN
            SET @outResultCode = 50051; -- falta o no existe el método de pago o de entrega
            RETURN;
        END;

        -- GP011 restricción 2: efectivo solo con retiro en el taller
        IF (@soloRetiro = @true)
            AND (@requiereDireccion = @true)
        BEGIN
            SET @outResultCode = 50053; -- efectivo solo para retiro
            RETURN;
        END;

        -- GP012 restricción 2: dirección obligatoria para métodos con envío.
        -- Se guarda una copia en texto (GP005 y GP006: el pedido conserva su dirección)
        IF (@requiereDireccion = @true)
        BEGIN
            IF (@inIdDireccion IS NULL)
            BEGIN
                SET @outResultCode = 50052; -- falta la dirección
                RETURN;
            END;

            SELECT @direccionTexto = D.OtrasSenas
                + N', ' + D.Distrito
                + N', ' + D.Canton
                + N', ' + PR.Nombre
            FROM dbo.Direccion AS D
            INNER JOIN dbo.Provincia AS PR
                ON (PR.IdProvincia = D.IdProvincia)
            WHERE (D.IdDireccion = @inIdDireccion)
                AND (D.IdUsuario = @inIdUsuario)
                AND (D.FlagActivo = @true);

            IF (@direccionTexto IS NULL)
            BEGIN
                SET @outResultCode = 50044; -- la dirección no existe
                RETURN;
            END;
        END
        ELSE
        BEGIN
            SET @direccionTexto = NULL; -- retiro en el taller: no se pide dirección
        END;

        -- GP013 restricción 2: comprobante obligatorio con SINPE Móvil.
        -- Si el método no lo usa, se ignora (efectivo: "Pago en efectivo al retirar")
        IF (@requiereComprobante = @true)
            AND (@rutaComprobante IS NULL)
        BEGIN
            SET @outResultCode = 50054; -- falta el comprobante
            RETURN;
        END;

        IF (@requiereComprobante = @false)
        BEGIN
            SET @rutaComprobante = NULL;
        END;

        IF (@rutaComprobante IS NOT NULL)
            AND (LOWER(@rutaComprobante) NOT LIKE N'%.png')
            AND (LOWER(@rutaComprobante) NOT LIKE N'%.jpg')
            AND (LOWER(@rutaComprobante) NOT LIKE N'%.jpeg')
        BEGIN
            SET @outResultCode = 50027; -- formato de imagen no permitido
            RETURN;
        END;

        BEGIN TRANSACTION tConfirmarOrden;

            -- GP014 paso 2.2: lee el carrito y BLOQUEA las existencias de esos
            -- productos hasta el COMMIT. Otra confirmación del mismo producto espera aquí
            INSERT INTO @lineas (
                IdCarritoDetalle
                , IdProductoTalla
                , IdProducto
                , NombreProducto
                , NombreTalla
                , PrecioUnitario
                , Cantidad
                , Existencias
                , FlagActivo
            )
            SELECT CD.IdCarritoDetalle
                , CD.IdProductoTalla
                , P.IdProducto
                , P.Nombre
                , T.Nombre
                , P.Precio -- precio vigente (GP020 paso 2.1)
                , CD.Cantidad
                , PT.Cantidad
                , P.FlagActivo
            FROM dbo.CarritoDetalle AS CD WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.ProductoTalla AS PT WITH (UPDLOCK, HOLDLOCK)
                ON (PT.IdProductoTalla = CD.IdProductoTalla)
            INNER JOIN dbo.Producto AS P WITH (HOLDLOCK)
                ON (P.IdProducto = PT.IdProducto)
            INNER JOIN dbo.Talla AS T
                ON (T.IdTalla = PT.IdTalla)
            WHERE (CD.IdUsuario = @inIdUsuario);

            -- el carrito pudo vaciarse mientras tanto (por ejemplo, confirmó en otra pestaña)
            IF NOT EXISTS (SELECT 1 FROM @lineas)
            BEGIN
                ROLLBACK TRANSACTION;
                SET @outResultCode = 50050; -- el carrito está vacío
                RETURN;
            END;

            -- GP014 flujo alterno 1 y criterio 1: algún producto ya no alcanza
            IF EXISTS (
                SELECT 1
                FROM @lineas AS L
                WHERE (L.FlagActivo = @false)
                    OR (L.Existencias < L.Cantidad)
            )
            BEGIN
                ROLLBACK TRANSACTION; -- no se registra ni se descuenta nada
                SET @outResultCode = 50055; -- productos no disponibles

                -- datos: cuáles productos fallaron, para marcarlos en el carrito
                SELECT L.IdCarritoDetalle
                    , L.IdProducto
                    , L.NombreProducto
                    , L.NombreTalla
                    , L.Cantidad
                    , CASE
                        WHEN (L.FlagActivo = @true) THEN L.Existencias
                        ELSE 0
                      END AS Disponibles
                FROM @lineas AS L
                WHERE (L.FlagActivo = @false)
                    OR (L.Existencias < L.Cantidad);
                RETURN;
            END;

            -- GP020 restricción 1: suma de (precio × cantidad) + envío si aplica
            SELECT @subtotalProductos = SUM(L.PrecioUnitario * L.Cantidad)
            FROM @lineas AS L;

            SET @total = @subtotalProductos + ISNULL(@costoEnvio, 0);

            -- GP014 paso 2.3: la orden, con estado "Pendiente de confirmación"
            INSERT INTO dbo.Pedido (
                IdUsuario
                , IdEstadoPedido
                , IdMetodoPago
                , IdMetodoEntrega
                , DireccionEntrega
                , SubtotalProductos
                , CostoEnvio
                , Total
                , MotivoEstado
                , FechaCreacion
            )
            VALUES (
                @inIdUsuario
                , @estadoPendiente
                , @inIdMetodoPago
                , @inIdMetodoEntrega
                , @direccionTexto
                , @subtotalProductos
                , @costoEnvio
                , @total
                , NULL
                , GETDATE()
            );

            SET @idPedido = SCOPE_IDENTITY(); -- número de pedido (criterio 3)

            -- el detalle guarda nombre, talla y precio del momento de la compra
            -- (ERS 2.4: el historial de ventas debe conservar los detalles)
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
                , L.IdProductoTalla
                , L.NombreProducto
                , L.NombreTalla
                , L.PrecioUnitario
                , L.Cantidad
                , (L.PrecioUnitario * L.Cantidad)
            FROM @lineas AS L;

            -- GP014 paso 2.2 y postcondición 2: descuenta del inventario
            UPDATE PT
            SET PT.Cantidad = PT.Cantidad - L.Cantidad
            FROM dbo.ProductoTalla AS PT
            INNER JOIN @lineas AS L
                ON (L.IdProductoTalla = PT.IdProductoTalla);

            -- GP013 restricción 3: el comprobante queda asociado solo a esta orden
            IF (@rutaComprobante IS NOT NULL)
            BEGIN
                INSERT INTO dbo.Comprobante (
                    IdPedido
                    , RutaArchivo
                    , FechaSubida
                )
                VALUES (
                    @idPedido
                    , @rutaComprobante
                    , GETDATE()
                );
            END;

            -- primer registro del historial del pedido (GP018)
            INSERT INTO dbo.HistorialEstadoPedido (
                IdPedido
                , IdEstadoPedido
                , IdUsuario
                , Comentario
                , FechaHora
            )
            VALUES (
                @idPedido
                , @estadoPendiente
                , @inIdUsuario
                , N'Orden registrada por el cliente'
                , GETDATE()
            );

            -- GP014 paso 2.4: vacía el carrito
            DELETE FROM dbo.CarritoDetalle
            WHERE (IdUsuario = @inIdUsuario);

        COMMIT TRANSACTION tConfirmarOrden;

        -- primer resultado: número de pedido y montos (GP014 paso 2.5).
        -- RutaComprobante NULL = no se guardó (pago en efectivo): el backend
        -- borra el archivo si el navegador mandó uno de todos modos
        SELECT @idPedido AS IdPedido
            , @subtotalProductos AS SubtotalProductos
            , @costoEnvio AS CostoEnvio
            , @total AS Total
            , @rutaComprobante AS RutaComprobante;

        -- segundo resultado: productos que cambiaron de existencias, para que el
        -- backend llame avisarCatalogo(idProducto) (CP010)
        SELECT DISTINCT L.IdProducto
        FROM @lineas AS L;

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
