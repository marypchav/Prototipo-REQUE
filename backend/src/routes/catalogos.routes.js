const { Router } = require('express');
const { envolver } = require('../utils/convertir');
const catalogos = require('../controllers/catalogos.controller');

const router = Router();

router.get('/', envolver(catalogos.obtenerCatalogos));

module.exports = router;
