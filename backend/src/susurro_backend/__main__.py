import argparse
import signal
import sys
import time


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Susurro TTS backend")
    parser.add_argument("--port", type=int, required=True, help="Port to listen on")
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    import susurro_backend.tts as tts
    from susurro_backend.server import app

    def handle_signal(signum, frame):
        sys.exit(0)

    signal.signal(signal.SIGINT, handle_signal)
    signal.signal(signal.SIGTERM, handle_signal)

    start = time.monotonic()
    tts.load_model()
    elapsed = time.monotonic() - start
    print(f"Model loaded in {elapsed:.2f}s")

    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=args.port, log_level="info")


if __name__ == "__main__":
    main()
