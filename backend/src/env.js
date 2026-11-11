/*
Lee y valida las variables del archivo .env.
Si falta alguna obligatoria, el servidor no arranca y dice cuál falta.
*/
require('dotenv').config();

const obligatorias = ['DB_SERVER', 'DB_NAME', 'DB_USER', 'DB_PASSWORD'];
const faltantes = obligatorias.filter((nombre) => !process.env[nombre]);

if (faltantes.length > 0) {
  console.error(`Faltan variables en el archivo .env: ${faltantes.join(', ')}`);
  console.error('Copie backend/.env.example como backend/.env y llénelo.');
  process.exit(1);
}

const instancia = (process.env.DB_INSTANCE || '').trim();

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
      // la base guarda las fechas con GETDATE() (hora de Costa Rica): se leen
      // como hora local y no como UTC, para que no se corran 6 horas
      useUTC: false,
      ...(instancia ? { instanceName: instancia } : {}),
    },
    pool: {
      max: 10,
      min: 0,
      idleTimeoutMillis: 30000,
    },
  },
};
