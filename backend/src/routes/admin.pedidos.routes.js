/*
CU3 y GI009. Todas pasan antes por requiereAdmin (routes/index.js).
*/
const { Router } = require('express');
const { envolver } = require('../utils/convertir');
const pedidos = require('../controllers/pedidos.controller');

const router = Router();

router.put('/pedidos/:id/estado', envolver(pedidos.cambiarEstado));
router.get('/ventas', envolver(pedidos.historialVentas));

module.exports = router;
