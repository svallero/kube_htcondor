from flask import Flask, abort
import htcondor
import socket
import os

app = Flask(__name__)

@app.route("/health")
def health():
  try:
    for schedd_ad in htcondor.Collector().locateAll(htcondor.DaemonTypes.Startd):
      #if schedd_ad['UidDomain'] == socket.gethostname(): 
      #if schedd_ad['UidDomain'] == "*": 
      #if '-submitter.marathon.occam-mesos' in schedd_ad['DedicatedScheduler']: 
      if 'executor' in schedd_ad['Machine']:
        return 'OK', 200
    abort(500) 
  except:
    abort(500) 

if __name__ == '__main__':
    app.run(host= '0.0.0.0')
    #app.run(host= socket.gethostbyname(socket.gethostname()))


