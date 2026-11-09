/*
GP019 Notificar al cliente el estado del pedido.

La base deja cada aviso en la tabla Notificacion (spCambiarEstadoPedido).
Aquí se envían los pendientes:
    - cada minuto (por si alguno falló, se reintenta: flujo alternativo)
    - y de inmediato cada vez que la administradora cambia un estado

Sin SMTP configurado en el .env, el correo se imprime en la terminal
y se marca como enviado: sirve para desarrollar y para la demostración.
*/
const nodemailer = require('nodemailer');
const config = require('../config/env');
const { ejecutarSP, sql } = require('../db/ejecutarSP');

const INTERVALO_MS = 60 * 1000;

const transporte = config.smtp.host
  ? nodemailer.createTransport({
      host: config.smtp.host,
      port: config.smtp.port,
      secure: config.smtp.port === 465,
      auth: { user: config.smtp.user, pass: config.smtp.pass },
    })
  : null;

let procesando = false; // evita dos vueltas al mismo tiempo

async function enviar(notificacion) {
  if (!transporte) {
    console.log(
      `\n[correo simulado] Para: ${notificacion.Correo}\n` +
        `Asunto: ${notificacion.Asunto}\n${notificacion.Mensaje}\n`
    );
    return;
  }
  await transporte.sendMail({
    from: config.smtp.from,
    to: notificacion.Correo,
    subject: notificacion.Asunto,
    text: notificacion.Mensaje,
  });
}

async function procesarNotificaciones() {
  if (procesando) {
    return;
  }
  procesando = true;

  try {
    const [pendientes] = await ejecutarSP('spListarNotificacionPendiente');

    for (const notificacion of pendientes) {
      let enviado = false;
      try {
        await enviar(notificacion);
        enviado = true;
      } catch (error) {
        console.error(`No se pudo enviar el correo ${notificacion.IdNotificacion}:`, error.message);
      }

      try {
        await ejecutarSP('spMarcarNotificacion', {
          inIdNotificacion: [sql.Int, notificacion.IdNotificacion],
          inFlagEnviado: [sql.Bit, enviado],
        });
      } catch (error) {
        console.error(`No se pudo marcar la notificación ${notificacion.IdNotificacion}:`, error.message);
      }
    }
  } catch (error) {
    console.error('Error al procesar notificaciones:', error.message);
  } finally {
    procesando = false;
  }
}

function iniciarEnvioPeriodico() {
  console.log(
    transporte
      ? `Correos: se envían por ${config.smtp.host}`
      : 'Correos: modo simulado (se imprimen aquí). Configure SMTP_HOST en el .env para enviarlos.'
  );
  procesarNotificaciones();
  setInterval(procesarNotificaciones, INTERVALO_MS);
}

module.exports = { procesarNotificaciones, iniciarEnvioPeriodico };
