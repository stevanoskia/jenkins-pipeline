"""Tiny Flask app used to demonstrate a Jenkins CI/CD pipeline.

The app itself is intentionally trivial; the interesting part is how it is
tested, packaged into an image and promoted from staging to prod.
"""

import os

from flask import Flask, jsonify, request


def create_app() -> Flask:
    app = Flask(__name__)

    @app.get("/")
    def index():
        return jsonify(
            message="Hello from jenkins-pipeline",
            env=os.getenv("APP_ENV", "local"),
        )

    @app.get("/health")
    def health():
        return jsonify(status="ok")

    @app.get("/version")
    def version():
        return jsonify(
            version=os.getenv("APP_VERSION", "dev"),
            git_sha=os.getenv("GIT_SHA", "unknown"),
        )

    @app.get("/add")
    def add():
        try:
            a = float(request.args["a"])
            b = float(request.args["b"])
        except (KeyError, ValueError):
            return jsonify(error="query parameters a and b must be numbers"), 400
        return jsonify(result=a + b)

    return app
