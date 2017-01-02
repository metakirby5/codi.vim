import os
import pty
import re
import select
import signal
import subprocess
from threading import Thread


class Codi(Thread):
    BUFSIZ = 1024
    ESCAPE = re.compile(r'(\x9B|\x1B\[)[0-?]*[ -\/]*[@-~]')

    def __init__(self, cmd, data, cb):
        Thread.__init__(self)
        self.data = data
        self.cmd = cmd
        self.cb = cb
        self.p = None

    def run(self):
        # Open a pseudoterminal
        master, slave = pty.openpty()
        self.p = subprocess.Popen(self.cmd,
                                  stdin=slave,
                                  stdout=slave,
                                  stderr=subprocess.STDOUT)
        output = ''

        # Loop for chances at I/O
        while self.p and self.p.poll() is None:
            r, w, _ = select.select([master], [master], [], 0)
            if r:
                output += self.ESCAPE.sub('', os.read(master, self.BUFSIZ))
            if w and self.data:
                self.data = self.data[os.write(master, self.data):]

        # Run the callback
        self.cb(output)

    def stop(self):
        if self.p:
            try:
                os.kill(self.p.pid, signal.SIGINT)
            except OSError:
                pass
            self.p = None

class CodiMgr(object):
    def __init__(self):
        self.codis = {}

    def start(self, buf, cmd, data, cb):
        job = Codi(cmd, data, cb)
        job.start()
        self.codis[buf] = job

    def stop(self, buf):
        try:
            job = self.codis.pop(buf)
        except KeyError:
            pass
        else:
            job.stop()

if __name__ == '__main__':
    def cb(output):
        print(output)
    codi_mgr = CodiMgr()
    codi_mgr.start(0, 'python', 'print "hello world"\nexit()\n', cb)
