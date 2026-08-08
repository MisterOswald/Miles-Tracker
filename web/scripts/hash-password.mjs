#!/usr/bin/env node
// Usage: npm run hash-password -- 'your-password'
// Prints a bcrypt hash to use as MILES_PASSWORD_HASH.
import bcrypt from "bcryptjs";

const password = process.argv[2];
if (!password) {
  console.error("Usage: npm run hash-password -- 'your-password'");
  process.exit(1);
}
console.log(bcrypt.hashSync(password, 12));
