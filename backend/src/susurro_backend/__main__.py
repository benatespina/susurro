import sys

from susurro_backend.handshake import AlreadyRunning, acquire_or_fail, register_cleanup


def main() -> None:
    try:
        port, token = acquire_or_fail()
    except AlreadyRunning as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)

    register_cleanup()

    from susurro_backend.server import create_app

    app = create_app(token)

    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=port, log_level="info")


if __name__ == "__main__":
    main()
