/*
GI001 Inicio de sesión como administrador, cierre de sesión y "quién soy".
El cierre de sesión y "quién soy" sirven también para el cliente (GP002);
su inicio de sesión está en clientes.controller.js.
*/
const bcrypt = require('bcryptjs');
const { ejecutarSP, sql } = require('./ejecutarSP');
const ErrorApp = require('./ErrorApp');
const { aTexto } = require('./convertir');
const { crearSesion, cerrarSesion } = require('./sesion');

// POST /api/sesion   cuerpo: { correo, contrasena }   (GI001)
async function iniciar(req, res) {
  const { correo, contrasena } = req.body ?? {};

  if (!correo || !contrasena) {
    throw new ErrorApp(50021); // campos obligatorios vacíos
  }

  // si el correo no es de una administradora activa, el SP devuelve 50020
  const [[usuario]] = await ejecutarSP('spObtenerCredencialAdmin', {
    inCorreo: [sql.NVarChar(150), aTexto(correo)],
  });

  let coincide = false;
  try {
    coincide = await bcrypt.compare(String(contrasena), usuario.PassHash);
  } catch {
    coincide = false; // hash inválido en la base
  }

  // GI001 flujo alternativo: el mismo mensaje, sin decir qué dato falló
  if (!coincide) {
    throw new ErrorApp(50020);
  }

  const sesion = crearSesion(res, usuario, { esAdministrador: true });
  res.json({ ok: true, datos: sesion });
}

// DELETE /api/sesion
async function cerrar(req, res) {
  cerrarSesion(res);
  res.json({ ok: true, mensaje: 'Sesión cerrada.' });
}

// GET /api/sesion   el frontend lo usa al cargar para saber quién está conectado
async function actual(req, res) {
  res.json({ ok: true, datos: req.usuario || null });
}

module.exports = { iniciar, cerrar, actual };
