# Códigos de error de BDCapanni

Todos los SP devuelven `@outResultCode`: **0 = éxito**. Cualquier otro número es un error.
El backend traduce el código al mensaje que ve el usuario (la ortografía de estos mensajes también se evalúa).

| Código | Significado | Mensaje sugerido para la interfaz | SP que lo devuelven |
|---|---|---|---|
| 50000 | Error inesperado (detalle en `dbo.dbError`) | Ocurrió un error. Intente de nuevo más tarde. | Todos |
| 50001 | Credenciales incorrectas o usuario inexistente | Correo o contraseña incorrectos. | spObtenerUsuarioLogin, spListarDireccion, spAgregarDireccion, spAgregarCarrito, spListarCarrito, spConfirmarOrden, spListarPedido |
| 50002 | Requiere rol de administración | No tiene permiso para realizar esta acción. | SP de inventario, spCambiarEstadoPedido, spHistorialVentas |
| 50003 | Campo obligatorio vacío | Complete todos los campos obligatorios. | spRegistrarCliente, spAgregarProducto, spActualizarProducto, direcciones |
| 50004 | Correo con formato inválido | Ingrese un correo electrónico válido. | spRegistrarCliente |
| 50005 | Correo ya registrado | Este correo ya está registrado. ¿Desea iniciar sesión? | spRegistrarCliente |
| 50006 | Teléfono inválido | El teléfono debe tener 8 dígitos. | spRegistrarCliente |
| 50007 | Categoría no existe | Seleccione una categoría válida. | spAgregarProducto, spActualizarProducto |
| 50008 | Precio inválido | El precio debe ser mayor que cero. | spAgregarProducto, spActualizarProducto |
| 50009 | Cantidad inválida | La cantidad debe ser un número entero válido. | spAgregarProducto, spActualizarDisponibilidad, carrito |
| 50010 | Talla inválida o lista de tallas inválida | Revise las tallas ingresadas. | spAgregarProducto, spActualizarDisponibilidad, spListarCatalogo |
| 50011 | Producto no existe o fue eliminado | Este producto ya no está disponible. | Inventario, spObtenerProducto |
| 50012 | Imagen con formato no permitido | Solo se permiten imágenes PNG o JPG. | spActualizarImagenProducto, spConfirmarOrden |
| 50013 | Provincia no existe | Seleccione una provincia válida. | Direcciones |
| 50014 | Dirección no existe o no es del cliente | La dirección no existe. | spActualizarDireccion, spEliminarDireccion |
| 50015 | Producto o talla no existe | Este producto ya no está disponible. | spAgregarCarrito |
| 50016 | Existencias insuficientes | No hay suficientes unidades disponibles. | spAgregarCarrito, spActualizarCarrito, spConfirmarOrden |
| 50017 | Carrito vacío | Su carrito está vacío. | spVaciarCarrito, spConfirmarOrden |
| 50018 | Línea del carrito no existe | El producto ya no está en su carrito. | spActualizarCarrito |
| 50019 | Método de pago no existe | Seleccione un método de pago. | spConfirmarOrden |
| 50020 | Método de entrega no existe | Seleccione un método de entrega. | spListarCarrito, spConfirmarOrden |
| 50021 | Efectivo solo con retiro en el taller | Disponible solo para retiro en el taller. | spConfirmarOrden |
| 50022 | Falta una dirección válida | Seleccione una dirección de envío. | spConfirmarOrden |
| 50023 | Falta el comprobante SINPE | Adjunte el comprobante de pago. | spConfirmarOrden |
| 50024 | Pedido no existe o sin acceso | El pedido no existe. | spObtenerPedido, spCambiarEstadoPedido |
| 50025 | Transición de estado no permitida | No se puede pasar el pedido a ese estado. | spCambiarEstadoPedido |
| 50026 | Falta el motivo | Indique el motivo del rechazo o la cancelación. | spCambiarEstadoPedido |
| 50027 | Notificación no existe o ya se envió | (uso interno del backend) | spMarcarNotificacion |

## Códigos que genera el backend (no vienen de la base)

| Código | Significado | HTTP |
|---|---|---|
| 50028 | Contraseña de menos de 8 caracteres (GP001) | 400 |
| 50029 | Imagen de más de 5 MB (GP013) | 400 |
| 50030 | Ruta que requiere iniciar sesión | 401 |
| 50031 | Ruta de la API que no existe | 404 |
| 50032 | JSON con formato inválido | 400 |

## SP por caso de uso

| Caso de uso | Requerimientos | Procedimientos |
|---|---|---|
| CU1 Gestión de inventario | GI001 a GI008 | spObtenerUsuarioLogin, spAgregarProducto, spActualizarImagenProducto, spListarProductoAdmin, spObtenerProducto, spActualizarProducto, spActualizarDisponibilidad, spEliminarProducto |
| CU2 Compra del cliente | CP001 a CP008, GP007 a GP014, GP020 | spListarCatalogo, spObtenerProducto, spAgregarCarrito, spListarCarrito, spActualizarCarrito, spVaciarCarrito, spConfirmarOrden |
| CU3 Atención de pedidos | GP015, GP016, GP017, GP019 | spListarPedido, spObtenerPedido, spCambiarEstadoPedido, spListarNotificacionPendiente, spMarcarNotificacion |
| CU4 Cuenta y direcciones | GP001 a GP006 | spRegistrarCliente, spObtenerUsuarioLogin, spListarDireccion, spAgregarDireccion, spActualizarDireccion, spEliminarDireccion |
| CU5 Historiales | GP018, GI009 | spListarPedido, spObtenerPedido, spHistorialVentas |
| Apoyo | | spObtenerCatalogos, spLimpiarBD |
