/*
Mapa de todas las rutas de la API. Todo cuelga de /api.

Públicas (cualquier visitante, CP009):
    POST   /api/auth/registro                    GP001
    POST   /api/auth/login                       GI001, GP002
    POST   /api/auth/logout
    GET    /api/auth/yo                          quién tiene la sesión abierta
    GET    /api/catalogos                        listas para formularios
    GET    /api/catalogo?categoria=1&tallas=2,3  CP001 a CP007
    GET    /api/productos/:id                    CP008

Cliente con sesión (y también la administradora):
    GET    /api/direcciones                      GP003
    POST   /api/direcciones                      GP004
    PUT    /api/direcciones/:id                  GP005
    DELETE /api/direcciones/:id                  GP006
    GET    /api/carrito?metodoEntrega=1          GP008, GP020
    POST   /api/carrito                          GP007
    PUT    /api/carrito/:id                      GP009 cambiar cantidad
    DELETE /api/carrito/:id                      GP009 quitar producto
    DELETE /api/carrito                          GP010
    POST   /api/pedidos                          GP011 a GP014 (multipart)
    GET    /api/pedidos?estado=1                 GP015 (admin: todos), GP018 (cliente: los suyos)
    GET    /api/pedidos/:id                      detalle con historial de estados
    GET    /api/pedidos/:id/comprobante          imagen del comprobante SINPE

Solo administradora:
    GET    /api/admin/productos?texto=&categoria=&talla=   GI004, GI008
    POST   /api/admin/productos                            GI002
    PUT    /api/admin/productos/:id                        GI005
    DELETE /api/admin/productos/:id                        GI006
    PUT    /api/admin/productos/:id/tallas/:idTalla        GI007
    POST   /api/admin/productos/:id/foto                   GI003 (multipart)
    PUT    /api/admin/pedidos/:id/estado                   GP016, GP017, GP019
    GET    /api/admin/ventas?desde=&hasta=                 GI009
*/
const { Router } = require('express');
const { requiereSesion, requiereAdmin } = require('../middlewares/autenticacion');

const router = Router();

// públicas
router.use('/auth', require('./auth.routes'));
router.use('/catalogos', require('./catalogos.routes'));
router.use('/catalogo', require('./catalogo.routes'));
router.use('/productos', require('./productos.routes'));

// con sesión
router.use('/direcciones', requiereSesion, require('./direcciones.routes'));
router.use('/carrito', requiereSesion, require('./carrito.routes'));
router.use('/pedidos', requiereSesion, require('./pedidos.routes'));

// solo administradora
router.use('/admin/productos', requiereAdmin, require('./admin.productos.routes'));
router.use('/admin', requiereAdmin, require('./admin.pedidos.routes'));

module.exports = router;
