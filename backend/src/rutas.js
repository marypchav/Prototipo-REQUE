/*
Todas las rutas de la API. Todo cuelga de /api (ver app.js).

Módulo Catálogo de productos (públicas, CP009):
    GET    /api/catalogo?categoria=1&tallas=2,3        CP001 a CP007
    GET    /api/productos/:id                          CP008, CP011

Sesión de la administradora (GI001):
    POST   /api/sesion                                 iniciar sesión
    DELETE /api/sesion                                 cerrar sesión
    GET    /api/sesion                                 quién está conectado

Módulo Gestión de inventario (solo la administradora):
    GET    /api/admin/opciones-producto                categorías y tallas del formulario
    GET    /api/admin/productos?busqueda=&categoria=&tallas=   GI004, GI008
    GET    /api/admin/productos/:id                    GI005 (cargar el formulario)
    POST   /api/admin/productos                        GI002
    PUT    /api/admin/productos/:id                    GI005
    PUT    /api/admin/productos/:id/existencias        GI007
    POST   /api/admin/productos/:id/foto               GI003 (multipart, campo "foto")
    DELETE /api/admin/productos/:id                    GI006

Módulo Gestión de pedidos, cuentas (públicas):
    POST   /api/clientes                               GP001 registrarse
    POST   /api/clientes/sesion                        GP002 iniciar sesión
    (cerrar sesión y "quién soy" son DELETE y GET /api/sesion)

Módulo Gestión de pedidos, del cliente (piden sesión de cliente):
    GET    /api/cliente/direcciones                    GP003 (y provincias)
    POST   /api/cliente/direcciones                    GP004
    PUT    /api/cliente/direcciones/:id                GP005
    DELETE /api/cliente/direcciones/:id                GP006
    GET    /api/cliente/carrito?metodoEntrega=1        GP008, GP020
    POST   /api/cliente/carrito                        GP007
    PUT    /api/cliente/carrito/:idDetalle             GP009 cambiar cantidad
    DELETE /api/cliente/carrito/:idDetalle             GP009 quitar un producto
    DELETE /api/cliente/carrito                        GP010 vaciar
    GET    /api/cliente/orden/opciones                 GP011, GP012
    POST   /api/cliente/pedidos                        GP013, GP014 (multipart, campo "comprobante")
    GET    /api/cliente/pedidos                        GP018
    GET    /api/cliente/pedidos/:id                    GP018 detalle
    GET    /api/cliente/pedidos/:id/comprobante        su comprobante

Módulo Gestión de pedidos, de la administradora:
    GET    /api/admin/pedidos?estado=1                 GP015
    GET    /api/admin/pedidos/:id                      GP015 detalle
    GET    /api/admin/pedidos/:id/comprobante          GP015 ver comprobante
    PUT    /api/admin/pedidos/:id/estado               GP016, GP017 (y correo GP019)
*/
const { Router } = require('express');
const { envolver } = require('./convertir');
const { requiereAdmin, requiereCliente } = require('./sesion');
const { subirFotoProducto, subirComprobante } = require('./subirImagen');
const catalogo = require('./catalogo.controller');
const sesion = require('./sesion.controller');
const inventario = require('./inventario.controller');
const clientes = require('./clientes.controller');
const direcciones = require('./direcciones.controller');
const carrito = require('./carrito.controller');
const pedidos = require('./pedidos.controller');

const router = Router();

// módulo Catálogo de productos
router.get('/catalogo', envolver(catalogo.listar));
router.get('/productos/:id', envolver(catalogo.obtener));

// sesión de la administradora
router.post('/sesion', envolver(sesion.iniciar));
router.delete('/sesion', envolver(sesion.cerrar));
router.get('/sesion', envolver(sesion.actual));

// módulo Gestión de inventario: todo lo de /admin pide sesión de administradora
router.use('/admin', requiereAdmin);
router.get('/admin/opciones-producto', envolver(inventario.opciones));
router.get('/admin/productos', envolver(inventario.listar));
router.get('/admin/productos/:id', envolver(inventario.obtener));
router.post('/admin/productos', envolver(inventario.agregar));
router.put('/admin/productos/:id', envolver(inventario.modificar));
router.put('/admin/productos/:id/existencias', envolver(inventario.actualizarExistencias));
router.post('/admin/productos/:id/foto', subirFotoProducto, envolver(inventario.subirFoto));
router.delete('/admin/productos/:id', envolver(inventario.eliminar));

// módulo Gestión de pedidos: pedidos de la administradora (ya pasaron por requiereAdmin)
router.get('/admin/pedidos', envolver(pedidos.listarAdmin));
router.get('/admin/pedidos/:id', envolver(pedidos.obtenerAdmin));
router.get('/admin/pedidos/:id/comprobante', envolver(pedidos.enviarComprobante));
router.put('/admin/pedidos/:id/estado', envolver(pedidos.cambiarEstado));

// módulo Gestión de pedidos: cuentas de cliente (públicas)
router.post('/clientes', envolver(clientes.registrar));
router.post('/clientes/sesion', envolver(clientes.iniciarSesion));

// módulo Gestión de pedidos: todo lo de /cliente pide sesión de cliente
router.use('/cliente', requiereCliente);
router.get('/cliente/direcciones', envolver(direcciones.listar));
router.post('/cliente/direcciones', envolver(direcciones.agregar));
router.put('/cliente/direcciones/:id', envolver(direcciones.modificar));
router.delete('/cliente/direcciones/:id', envolver(direcciones.eliminar));

router.get('/cliente/carrito', envolver(carrito.ver));
router.post('/cliente/carrito', envolver(carrito.agregar));
router.put('/cliente/carrito/:idDetalle', envolver(carrito.modificar));
router.delete('/cliente/carrito/:idDetalle', envolver(carrito.quitar));
router.delete('/cliente/carrito', envolver(carrito.vaciar));

router.get('/cliente/orden/opciones', envolver(pedidos.opcionesOrden));
router.post('/cliente/pedidos', subirComprobante, envolver(pedidos.confirmarOrden));
router.get('/cliente/pedidos', envolver(pedidos.listarDelCliente));
router.get('/cliente/pedidos/:id', envolver(pedidos.obtenerDelCliente));
router.get('/cliente/pedidos/:id/comprobante', envolver(pedidos.enviarComprobante));

module.exports = router;
