/*
Lee y valida las variables del archivo .env.
Si falta alguna obligatoria, el servidor no arranca y dice cuál falta.
*/
require('dotenv').config();

const obligatorias = ['DB_SERVER', 'DB_NAME', 'DB_USER', 'DB_PASSWORD', 'JWT_SECRET'];
const faltantes = obligatorias.filter((nombre) => !process.env[nombre]);

if (faltantes.length > 0) {
  console.error(`Faltan variables en el archivo .env: ${faltantes.join(', ')}`);
  console.error('Copie backend/.env.example como backend/.env y llénelo.');
  process.exit(1);
}

const instancia = (process.env.DB_INSTANCE || '').trim();
const horasSesion = Number(process.env.JWT_HORAS) || 8;

module.exports = {
  puerto: Number(process.env.PORT) || 3000,
  esProduccion: process.env.NODE_ENV === 'production',

  // configuración del paquete mssql
  db: {
    server: process.env.DB_SERVER,
    // con instancia con nombre (SQLEXPRESS) el puerto lo resuelve SQL Browser
    ...(instancia ? {} : { port: Number(process.env.DB_PORT) || 1433 }),
    database: process.env.DB_NAME,
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    options: {
      encrypt: process.env.DB_ENCRYPT === 'true',
      trustServerCertificate: true, // certificado autofirmado del SQL Server local
      ...(instancia ? { instanceName: instancia } : {}),
    },
    pool: {
      max: 10,
      min: 0,
      idleTimeoutMillis: 30000,
    },
  },

  jwt: {
    secreto: process.env.JWT_SECRET,
    horas: horasSesion,
  },

  // GP019: si host está vacío los correos se imprimen en la terminal
  smtp: {
    host: (process.env.SMTP_HOST || '').trim(),
    port: Number(process.env.SMTP_PORT) || 587,
    user: process.env.SMTP_USER || '',
    pass: process.env.SMTP_PASS || '',
    from: process.env.SMTP_FROM || 'Confecciones Capanni <no-responder@capanni.com>',
  },

  // GP013 restricción 1: imágenes de máximo 5 MB
  maxImagenMB: 5,
};
