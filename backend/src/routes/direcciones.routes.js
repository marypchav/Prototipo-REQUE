const { Router } = require('express');
const { envolver } = require('../utils/convertir');
const direcciones = require('../controllers/direcciones.controller');

const router = Router();

router.get('/', envolver(direcciones.listar));
router.post('/', envolver(direcciones.agregar));
router.put('/:id', envolver(direcciones.actualizar));
router.delete('/:id', envolver(direcciones.eliminar));

module.exports = router;
