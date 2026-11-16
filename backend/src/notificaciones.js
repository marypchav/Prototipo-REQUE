/*
GP019 Notificar al cliente el estado del pedido, por correo.

spCambiarEstadoPedido deja cada correo en la tabla Notificacion (cola).
Aquí se envían los pendientes:
  - enseguida después de cada cambio de estado (pedidos.controller.js)
  - y cada minuto, para reintentar los que fallaron (GP019 flujo alterno)
Cada intento queda registrado con spRegistrarEnvioNotificacion (postcondición 2).

Para que salgan los correos hace falta:
  1. npm install nodemailer        (en la carpeta backend)
  2. las líneas SMTP_* en el .env  (ver .env.example)
Sin eso el sistema funciona igual: los correos se quedan en la cola y el
cliente ve el estado en su historial de pedidos (GP019 restricción 2).
*/
const config = require('./env');
const { ejecutarSP, sql } = require('./ejecutarSP');

const CADA_MINUTO = 60 * 1000;
const MAX_INTENTOS = 5;

let transporte = undefined; // undefined = aún no se creó; null = correo desactivado
let enviando = false;

function crearTransporte() {
  if (!config.correo.host) {
    console.log('Correos de pedidos desactivados: falta SMTP_HOST en el .env (quedan en cola).');
    return null;
  }

  let nodemailer;
  try {
    nodemailer = require('nodemailer');
  } catch {
    console.log('Correos de pedidos desactivados: falta instalar nodemailer (npm install nodemailer).');
    return null;
  }

  return nodemailer.createTransport({
    host: config.correo.host,
    port: config.correo.puerto,
    secure: config.correo.seguro, // true con el puerto 465
    auth: config.correo.usuario ? { user: config.correo.usuario, pass: config.correo.clave } : undefined,
  });
}

async function registrarIntento(idNotificacion, enviado) {
  await ejecutarSP('spRegistrarEnvioNotificacion', {
    inIdNotificacion: [sql.Int, idNotificacion],
    inFlagEnviado: [sql.Bit, enviado],
  });
}

// envía todos los correos pendientes; si ya está enviando, no hace nada
async function enviarPendientes() {
  if (transporte === undefined) {
    transporte = crearTransporte();
  }
  if (!transporte || enviando) {
    return;
  }

  enviando = true;
  try {
    const [pendientes] = await ejecutarSP('spListarNotificacionesPendientes', {
      inMaxIntentos: [sql.Int, MAX_INTENTOS],
    });

    for (const notificacion of pendientes) {
      let enviado = false;
      try {
        await transporte.sendMail({
          from: config.correo.remitente,
          to: notificacion.Correo,
          subject: notificacion.Asunto,
          text: notificacion.Mensaje, // número de pedido, estado y motivo; nada sensible
        });
        enviado = true;
      } catch (error) {
        console.error(`No se pudo enviar el correo del pedido ${notificacion.IdPedido}:`, error.message);
      }
      await registrarIntento(notificacion.IdNotificacion, enviado);
    }
  } finally {
    enviando = false;
  }
}

// la llama server.js al arrancar
function iniciarNotificaciones() {
  const revisar = () =>
    enviarPendientes().catch((error) => console.error('Error al revisar los correos pendientes:', error.message));

  revisar();
  setInterval(revisar, CADA_MINUTO).unref(); // unref: no impide cerrar el servidor
}

module.exports = { enviarPendientes, iniciarNotificaciones };
