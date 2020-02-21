from flask import Flask, abort
import htcondor

app = Flask(__name__)

@app.route("/idle_jobs")
def idle_jobs():
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

@app.route("/running_jobs")
def running_jobs():
    try:
        schedd = htcondor.Schedd()
        num_running=0
        for job in schedd.xquery(projection=['JobStatus']):
            j = job.__repr__()
            if "JobStatus = 2" in j:
                num_running += 1
        return str(num_running), 200
    except:
        abort(401)

@app.route("/idle_nodes")
def idle_nodes():
    try:
        coll = htcondor.Collector()
        proj = coll.query(htcondor.AdTypes.Startd, projection=['Name', 'State', 'Activity'])
        num_idle=0
        for node in proj:
            state = node['State']
            activity = node['Activity']
            if (state == 'Unclaimed' and activity == 'Idle') or (state == 'Claimed' and activity == 'Benchmarking'): 
                num_idle += 1
        return str(num_idle), 200
    except:
        abort(401)

@app.route("/busy_nodes")
def busy_nodes():
    try:
        coll = htcondor.Collector()
        proj = coll.query(htcondor.AdTypes.Startd, projection=['Name', 'State', 'Activity'])
        num_busy=0
        for node in proj:
            state = node['State']
            activity = node['Activity']
            if (state == 'Claimed' and activity == 'Busy'): 
                num_busy += 1
        return str(num_busy), 200
    except:
        abort(401)

if __name__ == '__main__':
    app.run(host= '0.0.0.0', port = 5001)
