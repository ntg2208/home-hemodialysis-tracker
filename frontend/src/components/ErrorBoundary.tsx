import { Component, type ReactNode } from 'react';

interface Props { children: ReactNode; fallback?: ReactNode; }
interface State { error: Error | null; }

export class ErrorBoundary extends Component<Props, State> {
  state: State = { error: null };

  static getDerivedStateFromError(e: Error): State {
    return { error: e };
  }

  render() {
    if (this.state.error) {
      return this.props.fallback ?? (
        <div className="p-4 text-red-400">
          Something went wrong: {this.state.error.message}
          <button
            type="button"
            onClick={() => this.setState({ error: null })}
            className="ml-4 underline text-sm"
          >
            Retry
          </button>
        </div>
      );
    }
    return this.props.children;
  }
}
