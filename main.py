from flask import Flask, request
from werkzeug.utils import secure_filename
from dotenv import load_dotenv
import hmac
import os

load_dotenv()

app = Flask(__name__)
UPLOAD = os.getenv("UPLOAD_PATH", "/srv/drops")
PORT = int(os.getenv("PORT", "8080"))
PASSWORD = os.getenv("UPLOAD_PASSWORD", "")
os.makedirs(UPLOAD, exist_ok=True)

if not PASSWORD:
    raise RuntimeError("UPLOAD_PASSWORD is not set")


def check_password(value: str) -> bool:
    return hmac.compare_digest(value.encode(), PASSWORD.encode())


@app.route("/", methods=["GET"])
def form():
    return '''<form method=post enctype=multipart/form-data>
    <input type=password name=pwd placeholder=Mot de passe>
    <input type=file name=f>
    <input type=submit value=Envoyer>
    </form>'''


@app.route("/", methods=["POST"])
def upload():
    if not check_password(request.form.get("pwd", "")):
        return "Mot de passe incorrect", 403
    f = request.files["f"]
    filename = secure_filename(f.filename or "")
    if not filename:
        return "Nom de fichier invalide", 400
    f.save(os.path.join(UPLOAD, filename))
    return "Reçu, merci !"


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=PORT)
