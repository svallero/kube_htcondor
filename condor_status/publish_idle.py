from flask import Flask, abort
import htcondor

app = Flask(__name__)

@app.route("/idle")
def idle():
    try:
        schedd = htcondor.Schedd()
        num_idle=0
        for job in schedd.xquery(projection=['JobStatus']):
            j = job.__repr__()
            if "JobStatus = 1" in j:
                num_idle += 1
        return str(num_idle), 200
    except:
        abort(401)

if __name__ == '__main__':
    app.run(host= '0.0.0.0', port = 5001)

