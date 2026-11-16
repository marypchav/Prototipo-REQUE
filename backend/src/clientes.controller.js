/*
Módulo Gestión de pedidos: cuentas de cliente.
    GP001 Registrar cliente
    GP002 Iniciar sesión del cliente
El cierre de sesión y "quién soy" son los mismos de la administradora
(DELETE /api/sesion y GET /api/sesion, en sesion.controller.js).
*/
const bcrypt = require('bcryptjs');
const { ejecutarSP, sql } = require('./ejecutarSP');
const ErrorApp = require('./ErrorApp');
const { aTexto } = require('./convertir');
const { crearSesion } = require('./sesion');

const LARGO_MIN_CONTRASENA = 8; // GP001 restricción 3

function vacio(valor) {
  return valor === undefined || valor === null || String(valor).trim() === '';
}

// POST /api/clientes   (GP001)
// cuerpo: { nombre, correo, telefono, contrasena }
async function registrar(req, res) {
  const { nombre, correo, telefono, contrasena } = req.body ?? {};

  // GP001 restricción 1: ningún campo vacío
  if ([nombre, correo, telefono, contrasena].some(vacio)) {
    throw new ErrorApp(50021);
  }

  // GP001 restricción 3: se revisa ANTES del hash, porque al SP solo llega el hash
  if (String(contrasena).length < LARGO_MIN_CONTRASENA) {
    throw new ErrorApp(50043);
  }

  // la contraseña nunca se guarda en texto plano (postcondición 2)
  const passHash = await bcrypt.hash(String(contrasena), 10);

  // el SP valida formato del correo (50040), teléfono (50042) y correo repetido (50041)
  const [[fila]] = await ejecutarSP('spRegistrarCliente', {
    inNombre: [sql.NVarChar(100), aTexto(nombre)],
    inCorreo: [sql.NVarChar(200), aTexto(correo)],
    inTelefono: [sql.NVarChar(30), aTexto(telefono)],
    inPassHash: [sql.VarChar(100), passHash],
  });

  // GP001 paso 4.3: confirmación y a la pantalla de inicio de sesión (no inicia sola)
  res.status(201).json({
    ok: true,
    mensaje: 'Su cuenta fue creada. Ya puede iniciar sesión.',
    datos: { idUsuario: fila.IdUsuario },
  });
}

// POST /api/clientes/sesion   (GP002)
// cuerpo: { correo, contrasena }
async function iniciarSesion(req, res) {
  const { correo, contrasena } = req.body ?? {};

  if (vacio(correo) || vacio(contrasena)) {
    throw new ErrorApp(50021);
  }

  // si el correo no es de un cliente activo, el SP devuelve 50020.
  // Una cuenta de administradora tampoco entra por aquí (GP002 restricción 3)
  const [[usuario]] = await ejecutarSP('spObtenerCredencialCliente', {
    inCorreo: [sql.NVarChar(200), aTexto(correo)],
  });

  let coincide = false;
  try {
    coincide = await bcrypt.compare(String(contrasena), usuario.PassHash);
  } catch {
    coincide = false; // hash inválido en la base
  }

  // GP002 flujo alternativo: el mismo mensaje, sin decir qué dato falló
  if (!coincide) {
    throw new ErrorApp(50020);
  }

  const sesion = crearSesion(res, usuario, { esAdministrador: false });
  res.json({ ok: true, datos: sesion });
}

module.exports = { registrar, iniciarSesion };
