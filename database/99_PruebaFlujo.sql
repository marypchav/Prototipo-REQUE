/*
Prueba de punta a punta de la base, en el mismo orden de la demostración:
    CU1 la administradora agrega un producto
    CU4 una clienta se registra y guarda una dirección
    CU2 la clienta agrega al carrito y confirma la orden
    CU3 la administradora confirma y avanza el pedido
    CU5 se consultan los historiales

Cada paso muestra su ResultCode: todos deben salir en 0, menos los que
dicen "debe dar" otro código (son pruebas de los flujos alternativos).
Al final se puede dejar todo limpio con spLimpiarBD.
*/
USE BDCapanni;
GO

SET NOCOUNT ON;

DECLARE @r INT
    , @idAdmin INT
    , @idCliente INT
    , @idProducto INT
    , @idProductoTallaM INT
    , @idDireccion INT
    , @idPedido INT;

SELECT @idAdmin = U.IdUsuario
FROM dbo.Usuario AS U
WHERE (U.EsAdministrador = 1);

-------------------------------------------------------------------------------
-- CU1: inventario
-------------------------------------------------------------------------------
EXEC dbo.spAgregarProducto
    @inIdUsuario = @idAdmin
    , @inIP = '127.0.0.1'
    , @inIdCategoria = 1
    , @inNombre = N'Blusa floreada'
    , @inDescripcion = N'Blusa de algodón con estampado de flores'
    , @inPrecio = 12500
    , @inTallasJson = N'[{"IdTalla":2,"Cantidad":1},{"IdTalla":3,"Cantidad":1}]'
    , @outResultCode = @r OUTPUT;
SELECT 'spAgregarProducto' AS Paso, @r AS ResultCode;

SELECT @idProducto = MAX(P.IdProducto)
FROM dbo.Producto AS P;

SELECT @idProductoTallaM = PT.IdProductoTalla
FROM dbo.ProductoTalla AS PT
WHERE (PT.IdProducto = @idProducto)
    AND (PT.IdTalla = 3);

-- precio negativo: debe dar 50008
EXEC dbo.spAgregarProducto
    @inIdUsuario = @idAdmin
    , @inIP = '127.0.0.1'
    , @inIdCategoria = 1
    , @inNombre = N'Prueba'
    , @inDescripcion = NULL
    , @inPrecio = -5
    , @inTallasJson = N'[{"IdTalla":2,"Cantidad":1}]'
    , @outResultCode = @r OUTPUT;
SELECT 'precio inválido (debe dar 50008)' AS Paso, @r AS ResultCode;

EXEC dbo.spActualizarImagenProducto
    @inIdUsuario = @idAdmin
    , @inIP = '127.0.0.1'
    , @inIdProducto = @idProducto
    , @inRutaImagen = 'uploads/productos/blusa.jpg'
    , @outResultCode = @r OUTPUT;
SELECT 'spActualizarImagenProducto' AS Paso, @r AS ResultCode;

EXEC dbo.spActualizarProducto
    @inIdUsuario = @idAdmin
    , @inIP = '127.0.0.1'
    , @inIdProducto = @idProducto
    , @inIdCategoria = 1
    , @inNombre = N'Blusa floreada manga corta'
    , @inDescripcion = N'Blusa de algodón con estampado de flores'
    , @inPrecio = 13000
    , @outResultCode = @r OUTPUT;
SELECT 'spActualizarProducto' AS Paso, @r AS ResultCode;

EXEC dbo.spActualizarDisponibilidad
    @inIdUsuario = @idAdmin
    , @inIP = '127.0.0.1'
    , @inIdProducto = @idProducto
    , @inIdTalla = 4
    , @inCantidad = 2
    , @outResultCode = @r OUTPUT;
SELECT 'spActualizarDisponibilidad' AS Paso, @r AS ResultCode;

EXEC dbo.spListarCatalogo
    @inIdCategoria = NULL
    , @inTallasJson = N'[3]'
    , @outResultCode = @r OUTPUT;
SELECT 'spListarCatalogo' AS Paso, @r AS ResultCode;

-------------------------------------------------------------------------------
-- CU4: cuenta y direcciones
-------------------------------------------------------------------------------
EXEC dbo.spRegistrarCliente
    @inNombre = N'Ana Mora Solís'
    , @inCorreo = 'ana.prueba@gmail.com'
    , @inTelefono = '88112233'
    , @inPassHash = '$2b$10$hashDePrueba'
    , @inIP = '127.0.0.1'
    , @outResultCode = @r OUTPUT;
SELECT 'spRegistrarCliente' AS Paso, @r AS ResultCode;

-- mismo correo: debe dar 50005
EXEC dbo.spRegistrarCliente
    @inNombre = N'Otra Ana'
    , @inCorreo = 'ANA.prueba@gmail.com'
    , @inTelefono = '88112233'
    , @inPassHash = '$2b$10$hashDePrueba'
    , @inIP = '127.0.0.1'
    , @outResultCode = @r OUTPUT;
SELECT 'correo repetido (debe dar 50005)' AS Paso, @r AS ResultCode;

SELECT @idCliente = U.IdUsuario
FROM dbo.Usuario AS U
WHERE (U.Correo = 'ana.prueba@gmail.com');

EXEC dbo.spAgregarDireccion
    @inIdUsuario = @idCliente
    , @inIP = '127.0.0.1'
    , @inIdProvincia = 1
    , @inCanton = N'Desamparados'
    , @inDistrito = N'San Miguel'
    , @inOtrasSenas = N'200 m sur de la iglesia, casa verde'
    , @outResultCode = @r OUTPUT;
SELECT 'spAgregarDireccion' AS Paso, @r AS ResultCode;

SELECT @idDireccion = MAX(D.IdDireccion)
FROM dbo.Direccion AS D
WHERE (D.IdUsuario = @idCliente);

-------------------------------------------------------------------------------
-- CU2: carrito y orden
-------------------------------------------------------------------------------
EXEC dbo.spAgregarCarrito
    @inIdUsuario = @idCliente
    , @inIdProductoTalla = @idProductoTallaM
    , @inCantidad = 1
    , @outResultCode = @r OUTPUT;
SELECT 'spAgregarCarrito' AS Paso, @r AS ResultCode;

-- la talla M solo tiene 1: debe dar 50016
EXEC dbo.spAgregarCarrito
    @inIdUsuario = @idCliente
    , @inIdProductoTalla = @idProductoTallaM
    , @inCantidad = 1
    , @outResultCode = @r OUTPUT;
SELECT 'más de lo disponible (debe dar 50016)' AS Paso, @r AS ResultCode;

EXEC dbo.spListarCarrito
    @inIdUsuario = @idCliente
    , @inIdMetodoEntrega = 1
    , @outResultCode = @r OUTPUT;
SELECT 'spListarCarrito' AS Paso, @r AS ResultCode;

-- efectivo con envío por Correos: debe dar 50021
EXEC dbo.spConfirmarOrden
    @inIdUsuario = @idCliente
    , @inIP = '127.0.0.1'
    , @inIdMetodoPago = 2
    , @inIdMetodoEntrega = 1
    , @inIdDireccion = @idDireccion
    , @inRutaComprobante = NULL
    , @outResultCode = @r OUTPUT;
SELECT 'efectivo con envío (debe dar 50021)' AS Paso, @r AS ResultCode;

EXEC dbo.spConfirmarOrden
    @inIdUsuario = @idCliente
    , @inIP = '127.0.0.1'
    , @inIdMetodoPago = 1
    , @inIdMetodoEntrega = 1
    , @inIdDireccion = @idDireccion
    , @inRutaComprobante = 'uploads/comprobantes/sinpe1.jpg'
    , @outResultCode = @r OUTPUT;
SELECT 'spConfirmarOrden' AS Paso, @r AS ResultCode;

SELECT @idPedido = MAX(P.IdPedido)
FROM dbo.Pedido AS P
WHERE (P.IdUsuario = @idCliente);

-- la talla M debe haber quedado en 0
SELECT 'existencias talla M (debe ser 0)' AS Paso, PT.Cantidad
FROM dbo.ProductoTalla AS PT
WHERE (PT.IdProductoTalla = @idProductoTallaM);

-------------------------------------------------------------------------------
-- CU3: la administradora atiende el pedido
-------------------------------------------------------------------------------
EXEC dbo.spObtenerPedido
    @inIdUsuario = @idAdmin
    , @inIdPedido = @idPedido
    , @outResultCode = @r OUTPUT;
SELECT 'spObtenerPedido' AS Paso, @r AS ResultCode;

-- saltarse estados: debe dar 50025
EXEC dbo.spCambiarEstadoPedido
    @inIdUsuario = @idAdmin
    , @inIP = '127.0.0.1'
    , @inIdPedido = @idPedido
    , @inIdEstadoNuevo = 6
    , @inMotivo = NULL
    , @outResultCode = @r OUTPUT;
SELECT 'transición inválida (debe dar 50025)' AS Paso, @r AS ResultCode;

EXEC dbo.spCambiarEstadoPedido
    @inIdUsuario = @idAdmin
    , @inIP = '127.0.0.1'
    , @inIdPedido = @idPedido
    , @inIdEstadoNuevo = 2
    , @inMotivo = NULL
    , @outResultCode = @r OUTPUT;
SELECT 'confirmar pedido' AS Paso, @r AS ResultCode;

EXEC dbo.spCambiarEstadoPedido
    @inIdUsuario = @idAdmin
    , @inIP = '127.0.0.1'
    , @inIdPedido = @idPedido
    , @inIdEstadoNuevo = 3
    , @inMotivo = NULL
    , @outResultCode = @r OUTPUT;
SELECT 'en preparación' AS Paso, @r AS ResultCode;

EXEC dbo.spListarNotificacionPendiente
    @outResultCode = @r OUTPUT;
SELECT 'spListarNotificacionPendiente' AS Paso, @r AS ResultCode;

-------------------------------------------------------------------------------
-- CU5: historiales
-------------------------------------------------------------------------------
EXEC dbo.spListarPedido
    @inIdUsuario = @idCliente
    , @inIdEstadoPedido = NULL
    , @outResultCode = @r OUTPUT;
SELECT 'spListarPedido (cliente)' AS Paso, @r AS ResultCode;

EXEC dbo.spHistorialVentas
    @inIdUsuario = @idAdmin
    , @inFechaInicio = NULL
    , @inFechaFin = NULL
    , @outResultCode = @r OUTPUT;
SELECT 'spHistorialVentas' AS Paso, @r AS ResultCode;

-- errores inesperados que hayan quedado registrados (debe salir vacío)
SELECT *
FROM dbo.dbError
ORDER BY IdError DESC;

-- para dejar la base limpia:
-- EXEC dbo.spLimpiarBD @outResultCode = @r OUTPUT;

SET NOCOUNT OFF;
GO
