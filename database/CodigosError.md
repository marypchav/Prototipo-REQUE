# Códigos de error — módulo Catálogo de productos

Todos los SP devuelven `@outResultCode`: **0 = éxito**. Cualquier otro número es un error.
El backend traduce el código al mensaje que ve el usuario (`backend/src/codigosError.js`).

| Código | Significado | Mensaje para la interfaz | HTTP | Origen |
|---|---|---|---|---|
| 50000 | Error inesperado (detalle en `dbo.dbError`) | Ocurrió un error inesperado. Intente de nuevo más tarde. | 500 | Todos los SP |
| 50010 | Lista de tallas del filtro inválida | Revise las tallas ingresadas. | 400 | spListarCatalogo |
| 50011 | Producto no existe o fue eliminado | Este producto ya no está disponible. | 404 | spObtenerProducto |
| 50031 | Ruta de la API que no existe | La ruta solicitada no existe. | 404 | Backend |
| 50032 | JSON con formato inválido | Los datos enviados no tienen un formato válido. | 400 | Backend |

Los módulos Gestión de inventario y Gestión de pedidos agregan sus propios códigos
en esta tabla y en `codigosError.js`, sin repetir números.

## Procedimientos del módulo

| Procedimiento | Requerimientos |
|---|---|
| spListarCatalogo | CP001 a CP007, CP009 |
| spObtenerProducto | CP008, CP011 (el enlace compartido abre el detalle) |

CP010 (tiempo real) está en el backend: `backend/src/tiempoReal.js`.
CP011 (compartir) se completa en el frontend.
