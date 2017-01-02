import os
import pty
import re
import select
import subprocess
import vim
from threading import Thread


BUFSIZ = 1024
ESCAPE = re.compile(r'(\x9B|\x1B\[)[0-?]*[ -\/]*[@-~]')


class Codi(Thread):
    def __init__(self, data, cb):
        Thread.__init__(self)
        self.data = data
        self.cb = cb
        self.p = None

    def run(self):
        # Open a pseudoterminal
        master, slave = pty.openpty()
        self.p = subprocess.Popen('python',
                             stdin=slave,
                             stdout=slave,
                             stderr=subprocess.STDOUT)
        output = ''

        # Loop for chances at I/O
        while self.p.poll() is None:
            r, w, _ = select.select([master], [master], [], 0)
            if r:
                output += ESCAPE.sub('', os.read(master, BUFSIZ))
            if w and self.data:
                self.data = self.data[os.write(master, self.data):]

        # Run the callback
        vim.command(self.cb)

    def stop(self):
        if self.p:
            self.p.terminate()
            self.p = None
