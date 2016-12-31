#!/usr/bin/env julia

fb = open("/dev/fb0", "w")
width = 1280
height = 1024
nframes = 0
nsec = 10

frame = zeros(UInt32, width, height)
t0 = time()
while time() - t0 < nsec
    frame[:] = 0x00000000 + nframes
    seekstart(fb)
    write(fb, frame)
    #sleep(0.1)
    nframes += 1
end
fps = nframes / nsec
@show fps
