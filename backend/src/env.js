/*
Lee y valida las variables del archivo backend/.env.
Si algo falla, el servidor no arranca y dice exactamente qué pasa.
*/
const fs = require('fs');
const path = require('path');
const dotenv = require('dotenv');

// el .env se busca siempre en la carpeta backend, sin importar desde
// qué carpeta se haya abierto la terminal
const CARPETA_BACKEND = path.join(__dirname, '..');
const RUTA_ENV = path.join(CARPETA_BACKEND, '.env');

const lectura = dotenv.config({ path: RUTA_ENV });

// JWT_SECRET firma la cookie de la sesión de la administradora (GI001)
const obligatorias = ['DB_SERVER', 'DB_NAME', 'DB_USER', 'DB_PASSWORD', 'JWT_SECRET'];
const faltantes = obligatorias.filter((nombre) => !process.env[nombre]);

if (faltantes.length > 0) {
  console.error(`Faltan variables en el archivo .env: ${faltantes.join(', ')}`);

  if (!fs.existsSync(RUTA_ENV)) {
    // causas comunes: el archivo quedó con otro nombre o en otra carpeta
    const parecidos = fs
      .readdirSync(CARPETA_BACKEND)
      .filter((nombre) => nombre.toLowerCase().includes('env'));

    console.error(`No existe el archivo: ${RUTA_ENV}`);
    if (parecidos.length > 0) {
      console.error(`En backend hay estos archivos parecidos: ${parecidos.join(', ')}`);
      console.error('Renombre el correcto a exactamente ".env" (sin .txt ni nada más).');
    } else {
      console.error('Créelo en VS Code: clic derecho en backend -> Nuevo archivo -> .env');
    }
  } else if (lectura.parsed && Object.keys(lectura.parsed).length === 0) {
    // el archivo existe pero no se leyó ninguna variable
    console.error(`El archivo ${RUTA_ENV} existe pero no se leyó ninguna variable.`);
    console.error('Revise que esté guardado (Ctrl + S), que no esté vacío y que');
    console.error('la barra de abajo de VS Code diga UTF-8 (no UTF-16).');
  } else {
    console.error(`El archivo ${RUTA_ENV} existe pero le faltan esas líneas.`);
    console.error('Cada línea va como NOMBRE=valor, sin espacios antes del nombre.');
  }

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

  // sesión de la administradora (GI001)
  jwt: {
    secreto: process.env.JWT_SECRET,
    horas: Number(process.env.JWT_HORAS) || 8,
  },
};
