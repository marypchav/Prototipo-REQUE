/*
GI001 y GP002 Iniciar sesión, GP001 Registrar cliente, cerrar sesión.
*/
const bcrypt = require('bcryptjs');
const { ejecutarSP, sql } = require('../db/ejecutarSP');
const ErrorApp = require('../utils/ErrorApp');
const { aTexto, ipDe } = require('../utils/convertir');
const { crearSesion, cerrarSesion } = require('../middlewares/autenticacion');

const LARGO_MINIMO_CONTRASENA = 8; // GP001 restricción 3
const RONDAS_BCRYPT = 10;

// POST /api/auth/registro
async function registrar(req, res) {
  const { nombre, correo, telefono, contrasena } = req.body ?? {};

  if (typeof contrasena !== 'string' || contrasena.length < LARGO_MINIMO_CONTRASENA) {
    throw new ErrorApp(50028);
  }

  // a la base solo llega el hash, nunca la contraseña (sección 2.4)
  const passHash = await bcrypt.hash(contrasena, RONDAS_BCRYPT);

  const [[fila]] = await ejecutarSP('spRegistrarCliente', {
    inNombre: [sql.NVarChar(100), aTexto(nombre)],
    inCorreo: [sql.VarChar(128), aTexto(correo)],
    inTelefono: [sql.VarChar(16), aTexto(telefono)],
    inPassHash: [sql.VarChar(100), passHash],
    inIP: [sql.VarChar(64), ipDe(req)],
  });

  // GP001 paso 4.3: se confirma y el frontend lleva a iniciar sesión
  res.status(201).json({
    ok: true,
    mensaje: 'Cuenta creada con éxito. Ya puede iniciar sesión.',
    datos: { idUsuario: fila.IdUsuario },
  });
}

// POST /api/auth/login
async function iniciarSesion(req, res) {
  const { correo, contrasena } = req.body ?? {};

  if (!correo || !contrasena) {
    throw new ErrorApp(50001);
  }

  // si el correo no existe, el SP devuelve 50001
  const [[usuario]] = await ejecutarSP('spObtenerUsuarioLogin', {
    inCorreo: [sql.VarChar(128), aTexto(correo)],
  });

  let coincide = false;
  try {
    coincide = await bcrypt.compare(String(contrasena), usuario.PassHash);
  } catch {
    coincide = false; // hash inválido (por ejemplo, el de prueba sin reemplazar)
  }

  // GP002 flujo alternativo: mismo mensaje, sin decir qué dato falló
  if (!coincide) {
    throw new ErrorApp(50001);
  }

  const sesion = crearSesion(res, usuario);
  res.json({ ok: true, datos: sesion });
}

// POST /api/auth/logout
async function salir(req, res) {
  cerrarSesion(res);
  res.json({ ok: true });
}

// GET /api/auth/yo -> el frontend lo usa al cargar para saber quién está conectado
async function quienSoy(req, res) {
  res.json({ ok: true, datos: req.usuario || null });
}

module.exports = { registrar, iniciarSesion, salir, quienSoy };
