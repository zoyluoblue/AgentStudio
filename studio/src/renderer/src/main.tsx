import { createRoot } from "react-dom/client";
import { App } from "./App";
import { LangProvider } from "./i18n";
// Self-hosted fonts (bundled by Vite) — no runtime request to Google Fonts CDN.
import "@fontsource/inter/400.css";
import "@fontsource/inter/500.css";
import "@fontsource/inter/600.css";
import "@fontsource/inter/700.css";
import "@fontsource/inter/800.css";
import "@fontsource/inter/900.css";
import "@fontsource/jetbrains-mono/400.css";
import "@fontsource/jetbrains-mono/500.css";
// "fill" variant supports the wght + FILL axes the UI uses (FILL 0/1, wght 400);
// GRAD/opsz stay at their defaults, so it renders identically at ~1/4 the size of "full".
import "@fontsource-variable/material-symbols-outlined/fill.css";
import "./styles.css";

createRoot(document.getElementById("root")!).render(
  <LangProvider>
    <App />
  </LangProvider>,
);
