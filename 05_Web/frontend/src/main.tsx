import { StrictMode, Component, type ErrorInfo, type ReactNode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "@/App";
import "./index.css";

interface ErrorBoundaryProps {
  children: ReactNode;
}

interface ErrorBoundaryState {
  hasError: boolean;
  error: Error | null;
}

class ErrorBoundary extends Component<ErrorBoundaryProps, ErrorBoundaryState> {
  constructor(props: ErrorBoundaryProps) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error: Error): ErrorBoundaryState {
    return { hasError: true, error };
  }

  override componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    console.error("Uncaught application error:", error, errorInfo);
  }

  handleReload = () => {
    window.location.reload();
  };

  override render() {
    if (this.state.hasError) {
      return (
        <div style={{
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          height: "100vh",
          padding: "20px",
          textAlign: "center",
          background: "#0f172a",
          color: "#ffffff",
          fontFamily: "system-ui, sans-serif"
        }}>
          <h2 style={{ fontSize: "20px", fontWeight: "700", marginBottom: "8px", color: "#f87171" }}>
            Application Error Encountered
          </h2>
          <p style={{ fontSize: "13px", color: "#94a3b8", maxWidth: "480px", marginBottom: "16px" }}>
            An unexpected error occurred while rendering the GTWR Web Explorer:
          </p>
          <pre style={{
            fontSize: "11px",
            background: "rgba(0,0,0,0.5)",
            padding: "12px",
            borderRadius: "6px",
            color: "#fbbf24",
            maxWidth: "600px",
            overflowX: "auto",
            marginBottom: "20px"
          }}>
            {this.state.error?.message ?? "Unknown error"}
          </pre>
          <button
            onClick={this.handleReload}
            style={{
              padding: "8px 18px",
              background: "#2563eb",
              color: "#ffffff",
              border: "none",
              borderRadius: "6px",
              fontWeight: "600",
              cursor: "pointer"
            }}
          >
            Reload Explorer
          </button>
        </div>
      );
    }
    return this.props.children;
  }
}

const root = document.getElementById("root");
if (!root) throw new Error("Missing #root element");

createRoot(root).render(
  <StrictMode>
    <ErrorBoundary>
      <App />
    </ErrorBoundary>
  </StrictMode>,
);
