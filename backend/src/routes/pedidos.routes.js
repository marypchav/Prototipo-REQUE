const { Router } = require('express');
const { envolver } = require('../utils/convertir');
const pedidos = require('../controllers/pedidos.controller');
const { subirComprobante } = require('../middlewares/subirImagen');

const router = Router();

router.post('/', subirComprobante, envolver(pedidos.crear));
router.get('/', envolver(pedidos.listar));
router.get('/:id', envolver(pedidos.obtener));
router.get('/:id/comprobante', envolver(pedidos.verComprobante));

module.exports = router;
