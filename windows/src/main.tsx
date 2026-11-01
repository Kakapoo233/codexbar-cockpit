import React from "react";
import ReactDOM from "react-dom/client";
import "./styles.css";
import App from "./App";

document.documentElement.dataset.platform = /Windows/i.test(navigator.userAgent) ? "windows" : "preview";
ReactDOM.createRoot(document.getElementById("root")!).render(<React.StrictMode><App /></React.StrictMode>);
