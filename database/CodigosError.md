# Códigos de error

Todos los SP devuelven `@outResultCode`: **0 = éxito**. Cualquier otro número es un error.
El backend traduce el código al mensaje que ve el usuario (`backend/src/codigosError.js`).
Cada módulo usa su propio rango, sin repetir números.

## Generales

| Código | Significado | Mensaje para la interfaz | HTTP |
|---|---|---|---|
| 50000 | Error inesperado (detalle en `dbo.dbError`) | Ocurrió un error inesperado. Intente de nuevo más tarde. | 500 |

## Módulo Catálogo de productos (50010 a 50019)

| Código | Significado | Mensaje | HTTP | SP |
|---|---|---|---|---|
| 50010 | Lista de tallas del filtro inválida | Revise las tallas ingresadas. | 400 | spListarCatalogo, spListarInventario |
| 50011 | Producto no existe o fue eliminado | Este producto ya no está disponible. | 404 | spObtenerProducto y los SP de inventario |

## Módulo Gestión de inventario (50020 a 50029)

| Código | Significado | Mensaje | HTTP | SP |
|---|---|---|---|---|
| 50020 | Credenciales incorrectas | Correo o contraseña incorrectos. | 401 | spObtenerCredencialAdmin (y el backend si la contraseña no coincide) |
| 50021 | Campos obligatorios vacíos | Complete todos los campos obligatorios. | 400 | spObtenerCredencialAdmin, spAgregarProducto, spModificarProducto |
| 50022 | Precio inválido | El precio debe ser un número mayor que cero. | 400 | spAgregarProducto, spModificarProducto |
| 50023 | La categoría no existe | La categoría seleccionada no existe. | 400 | spAgregarProducto, spModificarProducto |
| 50024 | Cantidad negativa, decimal o con letras | Las cantidades deben ser números enteros, sin decimales, letras ni valores negativos. | 400 | spAgregarProducto, spModificarProducto, spActualizarExistencias |
| 50025 | Lista de tallas inválida | Revise las tallas ingresadas. | 400 | spAgregarProducto, spModificarProducto, spActualizarExistencias |
| 50026 | Ninguna talla con existencias | Ingrese existencias en al menos una talla. | 400 | spAgregarProducto |
| 50027 | Imagen que no es PNG ni JPG | Solo se permiten imágenes PNG o JPG. | 400 | spActualizarImagenProducto (y el backend al recibir el archivo) |

## Del backend (50031 en adelante)

| Código | Significado | Mensaje | HTTP |
|---|---|---|---|
| 50031 | Ruta de la API que no existe | La ruta solicitada no existe. | 404 |
| 50032 | JSON con formato inválido | Los datos enviados no tienen un formato válido. | 400 |
| 50033 | Ruta de administración sin sesión | Debe iniciar sesión para continuar. | 401 |
| 50034 | Sesión sin permiso para esa ruta (cliente en administración o al revés). También lo devuelve spCambiarEstadoPedido | No tiene permiso para realizar esta acción. | 403 |
| 50035 | Imagen de más de 5 MB | La imagen no puede superar los 5 MB. | 400 |
| 50036 | Se pidió subir foto sin enviar archivo | Seleccione una imagen. | 400 |
| 50037 | El pedido no tiene comprobante o el archivo ya no está | No se encontró el comprobante de pago. | 404 |

## Módulo Gestión de pedidos (50040 a 50059)

También usa 50011, 50020, 50021, 50027 y 50034, con el mismo significado de arriba.

| Código | Significado | Mensaje | HTTP | SP |
|---|---|---|---|---|
| 50040 | Correo con formato inválido | El correo electrónico no tiene un formato válido. | 400 | spRegistrarCliente |
| 50041 | Correo ya registrado | Este correo ya está registrado. Puede iniciar sesión con él. | 409 | spRegistrarCliente |
| 50042 | Teléfono inválido | El teléfono debe tener entre 8 y 16 dígitos. | 400 | spRegistrarCliente |
| 50043 | Contraseña de menos de 8 caracteres | La contraseña debe tener al menos 8 caracteres. | 400 | backend (antes del hash) |
| 50044 | La dirección no existe o es de otro cliente | La dirección seleccionada no existe. | 404 | spModificarDireccion, spEliminarDireccion, spConfirmarOrden |
| 50045 | La provincia no existe | La provincia seleccionada no existe. | 400 | spAgregarDireccion, spModificarDireccion |
| 50046 | Cantidad no entera o menor que 1 | La cantidad debe ser un número entero mayor que cero. | 400 | spAgregarAlCarrito, spModificarCarrito |
| 50047 | Talla agotada | Esta talla está agotada. | 400 | spAgregarAlCarrito |
| 50048 | Supera las existencias (trae Existencias y EnCarrito) | Solo hay N disponibles y ya tiene M en su carrito. | 400 | spAgregarAlCarrito, spModificarCarrito |
| 50049 | La línea no está en el carrito del cliente | Este producto ya no está en su carrito. | 404 | spModificarCarrito, spQuitarDelCarrito |
| 50050 | Carrito vacío | Su carrito está vacío. | 400 | spVaciarCarrito, spConfirmarOrden |
| 50051 | Falta o no existe el método de pago o de entrega | Seleccione un método de pago y un método de entrega. | 400 | spListarCarrito, spConfirmarOrden |
| 50052 | Falta la dirección para un envío | Seleccione una dirección de envío. | 400 | spConfirmarOrden |
| 50053 | Efectivo con un método que no es retiro | El pago en efectivo está disponible solo para retiro en el taller. | 400 | spConfirmarOrden |
| 50054 | SINPE Móvil sin comprobante | Adjunte el comprobante de pago de SINPE Móvil. | 400 | spConfirmarOrden |
| 50055 | Productos que ya no alcanzan (trae la lista) | Algunos productos ya no están disponibles. Revise su carrito. | 409 | spConfirmarOrden |
| 50056 | El pedido no existe o es de otro cliente | El pedido no existe. | 404 | spObtenerPedido, spCambiarEstadoPedido |
| 50057 | Transición de estado no permitida | Ese cambio de estado no está permitido. | 409 | spCambiarEstadoPedido |
| 50058 | Rechazar o cancelar sin motivo | Escriba el motivo. | 400 | spCambiarEstadoPedido |
| 50059 | La notificación no existe | La notificación no existe. | 404 | spRegistrarEnvioNotificacion |
