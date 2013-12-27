GA = /home/dave/usr/local/ga-5-2
WORKQ = ./workq
BLAS = /home/dave/usr/local/openblas64


all:
	#mpicc -I ${GA}/include -L${GA}/lib psp.c -o psp -lga -larmci
	mpif77 -g -fdefault-integer-8 -I ${GA}/include -L${GA}/lib psp.F -L${WORKQ} -L${BLAS}/lib -o psp -lga -larmci -lworkq -lopenblas
	mpicc -g -I ${GA}/include -I ${BLAS}/include -L${GA}/lib psp.c -L${WORKQ} -L${BLAS}/lib -o cpsp -lga -larmci -lworkq -lopenblas

tau:
	tau_f77.sh -fdefault-integer-8 -I ${GA}/include -L${GA}/lib psp.F -L${WORKQ} -L${BLAS}/lib -o psp.tau -lga -larmci -lworkq -lopenblas

clean:
	rm psp.o psp psp.tau
