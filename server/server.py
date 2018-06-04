import socket

port = 12345

s = socket.socket()
host = '192.168.1.32'

s.bind((host, port))

s.listen(5)
print( 'Listening on', host, ':', str(port) )

with open('datafile', 'a') as f:

    while True:
        print('Sleeping...')
        
        c, addr = s.accept()
        print('Got connection from ', addr)
        try:
            while True:
                data = c.recv(1024)
                if not data:
                    break
                f.write(str(data))
                f.write('\n')
                print('.')
        except:
            print('Dropped connection. Will try to restart...')
        c.close()
        print('Connection closed.')
        f.flush()


