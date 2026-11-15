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
| 50034 | Sesión sin permiso de administración | No tiene permiso para realizar esta acción. | 403 |
| 50035 | Imagen de más de 5 MB | La imagen no puede superar los 5 MB. | 400 |
| 50036 | Se pidió subir foto sin enviar archivo | Seleccione una imagen. | 400 |

El módulo Gestión de pedidos usa el rango 50040 a 50059.
