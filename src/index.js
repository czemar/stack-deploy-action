import { $ } from "npm:zx";

// List repository files
const dir = await $`ls -la`;

console.log(dir);