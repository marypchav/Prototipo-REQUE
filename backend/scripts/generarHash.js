/*
Genera el hash bcrypt de la contraseña de la administradora y escribe el
UPDATE listo para copiar en SSMS.

Uso (desde la carpeta backend):
    npm run hash -- "LaContraseñaDeCarmen"
*/
const bcrypt = require('bcryptjs');

const contrasena = process.argv[2];

if (!contrasena || contrasena.length < 8) {
  console.error('Uso: npm run hash -- "LaContraseña"   (mínimo 8 caracteres)');
  process.exit(1);
}

const hash = bcrypt.hashSync(contrasena, 10);

console.log('\nCopie y ejecute esto en SSMS:\n');
console.log('USE BDCapanni;');
console.log(`UPDATE dbo.Usuario SET PassHash = '${hash}' WHERE (EsAdministrador = 1);\n`);
