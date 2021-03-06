      program bench
      implicit none
#include "mpif.h"
#include "mafdecls.fh"
#include "global.fh"
#include "errquit.fh"
c     Carver 8n/8ppn
#define LOCAL_BUFLEN 1093475
c#define LOCAL_BUFLEN 2000000
c     ACISS 8n/8ppn
c#define LOCAL_BUFLEN 3093475
c#define LOCAL_BUFLEN 100
c#define LOCAL_BUFLEN 10
      integer ierr, me, nproc, heap, stack, tot_data_size, ga_cnt
      integer g_a, g_b, g_c, chunk, i, ihi, ilo, jhi, jlo, ld
      integer msqids(7)
      integer tile_dim, num_collectors
      character(len=32) :: arg
      double precision buf(LOCAL_BUFLEN), t2, t1, nm
      logical status, verif

      character*(256) hostname

c     Carver 8 ppn:
      heap = 200000000
      stack = 25435450

c     ACISS 12 ppn:
c     heap = 200000000
c     stack = 50000000

      verif = .true.

      call mpi_init(ierr)
      call ga_initialize()

      me = ga_nodeid()
      nproc = ga_nnodes()
      tot_data_size = nproc * LOCAL_BUFLEN

c   Command line Arguments (tile_size and num collector procs)
 20   format (a,2x,i5)
      call getarg(1, arg)
      read (arg,*) tile_dim
      if(me.eq.0) write(*, 20), "tile_dim:", tile_dim

      call getarg(2, arg)
      read (arg,*) num_collectors
      if(me.eq.0) write(*, 20), "num_collectors:", num_collectors 


      if (.not.ma_init(MT_DBL, stack, heap))
     +   call ga_error("ma_init failed",-1)
      call flush(6)

c   This mimics the creation of T2/V2 in tce_energy.F
      status = ga_create(MT_DBL, LOCAL_BUFLEN*nproc, 1, 
     &                   "ga:A", -1, 1, g_a)
      if (.not.status) call pexit('ga_create(A) fail')
      status = ga_create(MT_DBL, LOCAL_BUFLEN*nproc, 1, 
     &                   "ga:B", -1, 1, g_b)
      if (.not.status) call pexit('ga_create(B) fail')
      status = ga_create(MT_DBL, LOCAL_BUFLEN*nproc, 1, 
     &                   "ga:C", -1, 1, g_c)
      if (.not.status) call pexit('ga_create(C) fail')

      ilo = me*LOCAL_BUFLEN + 1
      ihi = ilo + LOCAL_BUFLEN - 1
      ld = LOCAL_BUFLEN*nproc

c   Populate GA with synthetic data (GA[i] = i)
      do i=1,LOCAL_BUFLEN
        buf(i) = dble(LOCAL_BUFLEN*me) + i
      end do

      call ga_put(g_a, ilo, ihi, 1, 1, buf, ld)
      call ga_put(g_b, ilo, ihi, 1, 1, buf, ld)
      call ga_zero(g_c)

 10   format (a,2x,f10.6)

      t1 = ga_wtime()
      call bench_orig(g_a, g_b, g_c, tile_dim)
      call ga_sync()
      t2 = ga_wtime()
      if(me.eq.0) write(*, 10), "bench_orig:", t2 - t1

      if (verif) then
        call ga_norm1(g_c, nm)
        if(me.eq.0) write(*,*), "norm(C):", nm 
        call ga_zero(g_c)  
      end if

c     t1 = ga_wtime()
c     call bench_orig_stats(g_a, g_b, g_c, tile_dim)
c     call ga_sync()
c     t2 = ga_wtime()
c     if(me.eq.0) write(*, 10), "bench_orig_stats:", t2 - t1

c     t1 = ga_wtime()
c     call bench_nb(g_a, g_b, g_c)
c     call ga_sync()
c     t2 = ga_wtime()
c     if(me.eq.0) write(*, 10), "bench_nb:", t2 - t1

      t1 = ga_wtime()
      call bench_workq(g_a, g_b, g_c,.true.,ga_cnt,msqids,
     &                 tile_dim, num_collectors)
      call ga_sync()
      t2 = ga_wtime()
      if(me.eq.0) write(*, 10), "bench_workq:", t2 - t1

      if (verif) then
        call ga_norm1(g_c, nm)
        if(me.eq.0) write(*,*), "norm(C):", nm 
        call ga_zero(g_c)  
      end if

c     call ga_print(g_a)
c     call ga_print(g_c)

      status = ga_destroy(g_a)
      if (.not.status) call pexit('ga_destroy(A) fail')
      status = ga_destroy(g_b)
      if (.not.status) call pexit('ga_destroy(B) fail')
      status = ga_destroy(g_c)
      if (.not.status) call pexit('ga_destroy(C) fail')
      call ga_terminate()
      call mpi_finalize(ierr)

      end program bench


c     Original version
      subroutine bench_orig(g_a, g_b, g_c, tile_dim)
      implicit none
#include "global.fh"
#include "mafdecls.fh"
#include "errquit.fh"
      integer g_a, g_b, g_c, me, nproc, num_nodes, nodeid, ch, ppn
      integer ga_cnt, count, next, i, j, ilo, ihi, ld, tot_data_size
      double precision bufa(LOCAL_BUFLEN)
      double precision bufb(LOCAL_BUFLEN)
      double precision bufc(LOCAL_BUFLEN)
      double precision time1, time2, total_time
      logical status
      integer tile_dim, tile_size
      integer k

      time1 = ga_wtime()
      tile_size = tile_dim*tile_dim

      call ga_cluster_info(num_nodes, nodeid, ch, ppn)
      me = ga_nodeid()
      nproc = ga_nnodes()
      tot_data_size = nproc * LOCAL_BUFLEN

c   Create a global counter for dynamic load balancing
      status = nga_create(MT_INT, 1, 1, 'counter', 1, ga_cnt)
      if (.not.status) call pexit('get_task() fail')
      CALL ga_zero(ga_cnt)

      count = 0
      next = nga_read_inc(ga_cnt, 1, 1)
      do i=0,tot_data_size/tile_size-1
        if (next.eq.count) then
          bufc = 0
          ilo = next*tile_size + 1
          ihi = ilo + tile_size - 1
          ld = LOCAL_BUFLEN*nproc

          call ga_get(g_a, ilo, ihi, 1, 1, bufa, ld)
          call ga_get(g_b, ilo, ihi, 1, 1, bufb, ld)

          call dgemm_wrap(tile_dim, bufa, bufb, bufc)
          call ga_put(g_c, ilo, ihi, 1, 1, bufc, tile_dim)

          next = nga_read_inc(ga_cnt, 1, 1)
        end if
        count = count + 1
      end do

      time2 = ga_wtime()
      total_time = time2 - time1

c     if(me.eq.0) write(*, 10), "bench_orig:", total_time
c10   format (a,2x,f10.6)

      return
      end

c     Statistics version
      subroutine bench_orig_stats(g_a, g_b, g_c, tile_dim)
      implicit none
#include "global.fh"
#include "mafdecls.fh"
#include "errquit.fh"
      integer g_a, g_b, g_c, me, nproc, num_nodes, nodeid, ch, ppn
      integer ga_cnt, count, next, i, j, ilo, ihi, ld, tot_data_size
      double precision bufa(LOCAL_BUFLEN)
      double precision bufb(LOCAL_BUFLEN)
      double precision bufc(LOCAL_BUFLEN)
      double precision time1, time2, total_time
      logical status
      integer tile_dim, tile_size
      integer k
      double precision t2, t1, time

      time1 = ga_wtime()
      tile_size = tile_dim*tile_dim

      call ga_cluster_info(num_nodes, nodeid, ch, ppn)
      me = ga_nodeid()
      nproc = ga_nnodes()
      tot_data_size = nproc * LOCAL_BUFLEN

c   Create a global counter for dynamic load balancing
      status = nga_create(MT_INT, 1, 1, 'counter', 1, ga_cnt)
      if (.not.status) call pexit('get_task() fail')
      CALL ga_zero(ga_cnt)

      count = 0
      next = nga_read_inc(ga_cnt, 1, 1)
      do i=0,tot_data_size/tile_size-1
        if (next.eq.count) then
          bufc = 0
          ilo = next*tile_size + 1
          ihi = ilo + tile_size - 1
          ld = LOCAL_BUFLEN*nproc

          t2 = ga_wtime()
          call ga_get(g_a, ilo, ihi, 1, 1, bufa, ld)
          t1 = ga_wtime()
          time = t2 - t1
          print *, "get(a)", time

          t2 = ga_wtime()
          call ga_get(g_b, ilo, ihi, 1, 1, bufb, ld)
          t1 = ga_wtime()
          time = t2 - t1
          print *, "get(b)", time

          t2 = ga_wtime()
          call dgemm_wrap(tile_dim, bufa, bufb, bufc)
          t1 = ga_wtime()
          time = t2 - t1
          print *, "dgemm()", time

          t2 = ga_wtime()
          call ga_put(g_c, ilo, ihi, 1, 1, bufc, tile_dim)
          t1 = ga_wtime()
          time = t2 - t1
          print *, "add(c)", time

          next = nga_read_inc(ga_cnt, 1, 1)
        end if
        count = count + 1
      end do

      time2 = ga_wtime()
      total_time = time2 - time1

c     if(me.eq.0) write(*, 10), "bench_orig:", total_time
c10   format (a,2x,f10.6)

      return
      end



      integer function swap_color(color)
      integer color
      if (color.eq.1) then
        swap_color = 2
      else
        swap_color = 1
      end if
      return
      end

c     Non-blocking version (not fully implemented yet):
      subroutine bench_nb(g_a, g_b, g_c, tile_dim)
      implicit none
#include "global.fh"
#include "mafdecls.fh"
#include "errquit.fh"
      integer g_a, g_b, g_c, me, nproc, num_nodes, nodeid, ch, ppn
      integer ga_cnt, count, next, i, j, ilo, ihi, ld, tot_data_size
      double precision bufa(LOCAL_BUFLEN, 2)
      double precision bufb(LOCAL_BUFLEN, 2)
      double precision bufc(LOCAL_BUFLEN, 2)
      double precision time1, time2, total_time
      logical status
      integer tile_dim, tile_size
      integer handle_a(2), handle_b(2)
      integer iter, prev_id, color, prev_color, k
      integer swap_color

      time1 = ga_wtime()
      tile_size = tile_dim*tile_dim

      call ga_cluster_info(num_nodes, nodeid, ch, ppn)
      me = ga_nodeid()
      nproc = ga_nnodes()
      tot_data_size = nproc * LOCAL_BUFLEN

c   Create a global counter for dynamic load balancing
      status = nga_create(MT_INT, 1, 1, 'counter', 1, ga_cnt)
      if (.not.status) call pexit('get_task() fail')
      CALL ga_zero(ga_cnt)

      count = 0
      next = nga_read_inc(ga_cnt, 1, 1)
      ld = LOCAL_BUFLEN*nproc
      iter = 1
      prev_id = 0
      color = 2
      prev_color = 1

c     TODO: last task...
      do i=0,tot_data_size/tile_size-2
        if (next.eq.count) then
        bufc = 0

        if (iter.eq.1) then
          do j=1,2
            ilo = (next+j-1)*tile_size + 1
            ihi = ilo + tile_size - 1
            call ga_nbget(g_a, ilo, ihi, 1, 1, bufa(1,j),ld,handle_a(j))
            call ga_nbget(g_b, ilo, ihi, 1, 1, bufb(1,j),ld,handle_b(j))
          end do
          ilo = (next)*tile_size + 1
          ihi = ilo + tile_size - 1
          call ga_nbwait(handle_a(1))
          call ga_nbwait(handle_b(1))
        else
          call ga_nbwait(handle_a(color))
          call ga_nbwait(handle_b(color))
          prev_color = color
          color = swap_color(color)

          ilo = (next+1)*tile_size + 1;
          ihi = ilo + tile_size - 1;
          call ga_nbget(g_a, ilo, ihi, 1, 1, bufa(1,color), ld,
     &                  handle_a(color))
          call ga_nbget(g_b, ilo, ihi, 1, 1, bufb(1,color), ld,
     &                  handle_b(color))
          ilo = (prev_id)*tile_size + 1;
          ihi = ilo + tile_size - 1;

        end if

        call dgemm_wrap(tile_dim, bufa, bufb, bufc)

          call ga_put(g_c, ilo, ihi, 1, 1, bufc, tile_dim)

          prev_id = next + 1
          next = nga_read_inc(ga_cnt, 1, 1)
          iter = iter + 1
        end if
        count = count + 1
      end do

      time2 = ga_wtime()
      total_time = time2 - time1

c     if(me.eq.0) write(*, 10), "bench_nb:", total_time
c10   format (a,2x,f10.6)

      return
      end

      subroutine dgemm_wrap(tile_dim, bufa, bufb, bufc)
      integer tile_dim
      double precision bufa(LOCAL_BUFLEN)
      double precision bufb(LOCAL_BUFLEN)
      double precision bufc(LOCAL_BUFLEN)

          call dgemm( 'T', 'N', tile_dim, tile_dim, tile_dim, 1.0d0, 
     &                 bufa, tile_dim, bufb, tile_dim, 1.0, bufc, 
     &                 tile_dim)
      return
      end

      subroutine bench_workq(g_a, g_b, g_c, init, ga_cnt, msqids,
     &                       tile_dim, num_collectors)
      implicit none
#include "global.fh"
#include "mafdecls.fh"
#include "errquit.fh"
      integer g_a, g_b, g_c, me, nproc, num_nodes, nodeid, ch, ppn
      integer ga_cnt, count, next, i, j, ilo, ihi, ld, tot_data_size
      double precision bufa(LOCAL_BUFLEN)
      double precision bufb(LOCAL_BUFLEN)
      double precision time1, time2, total_time, t1, t2
      logical status, a_collector, am_collector, init
      integer num_collectors, msqids(7), sem, collector
      integer tile_dim, tile_size

      time1 = ga_wtime()
      tile_size = tile_dim*tile_dim
      sem = 0

      call ga_cluster_info(num_nodes, nodeid, ch, ppn)
      me = ga_nodeid()
      nproc = ga_nnodes()
      tot_data_size = nproc * LOCAL_BUFLEN

c     The zeroeth proc on each node is that node's collector:
      collector = me - mod(me,ppn)
      a_collector = am_collector(me, collector, num_collectors) 

      if (init) then 
        call workq_create_queue(me, collector, msqids, nodeid, ppn)
      end if

c   Create a global counter for dynamic load balancing
      if (init) then
        status = nga_create(MT_INT, 1, 1, 'counter', 1, ga_cnt)
        if (.not.status) call pexit('get_task() fail')
        CALL ga_zero(ga_cnt)
      end if

      count = 0
      next = nga_read_inc(ga_cnt, 1, 1)

c     CALL workq_sem_getvalue(sem, nodeid)
      CALL workq_sem_post(nodeid)

      do i=0,tot_data_size/tile_size-1
        if (next.eq.count) then

c         CALL workq_sem_getvalue(sem, nodeid)
c         print *, "sem value = ", sem

          CALL workq_alloc_task(next, tile_size*2)

          ilo = next*tile_size + 1
          ihi = ilo + tile_size - 1
          ld = LOCAL_BUFLEN*nproc
  
c         call ga_get(g_a, ilo, ihi, 1, 1, bufa, ld)
c         call ga_get(g_b, ilo, ihi, 1, 1, bufb, ld)
          t1 = ga_wtime()
          call workq_append_task_single(next, tile_dim, g_a, g_b, 
     &                                       ld, bufa, bufb)
          t2 = ga_wtime()
c         write(*, 20), "GET(", me, "):", t2 - t1
c20     format (a,i2,a,2x,f10.6)
          call workq_enqueue_single(msqids, next, tile_dim, me, nodeid,
     &                         ppn, a_collector)

          CALL workq_sem_release(nodeid)

          if (.not.a_collector) then
              CALL worker(g_a, g_b, g_c, ga_cnt, msqids, tile_dim, 
     &                    num_collectors)
              return
          end if 

          next = nga_read_inc(ga_cnt, 1, 1)
          CALL workq_sem_post(nodeid)
        end if
        count = count + 1
      end do

c     if(me.eq.0) write(*,11), "total tasks: ", count
 11   format (a,2x,i5)

      CALL workq_sem_release(nodeid)
      CALL workq_sem_wait()
      time2 = ga_wtime()
      total_time = time2 - time1

      if (me.eq.collector) then
        CALL workq_end_taskgroup(msqids, ppn, count)
      end if

      CALL worker(g_a, g_b, g_c, ga_cnt, msqids, tile_dim,
     &            num_collectors)

c     if(me.eq.0) write(*, 10), "bench_workq:", total_time
c10   format (a,2x,f10.6)

      return
      end


      subroutine worker(g_a, g_b, g_c, ga_cnt, msqids, td, 
     &                  num_collectors)
      implicit none
#include "global.fh"
      integer g_a, g_b, g_c, ga_cnt, msqids(7), num_collectors, nproc
      integer me, num_nodes, nodeid, collector, collector_host, ppn
      integer more_tasks,data_size,task_id,qlen,qid,nc,data_id,key,shmid
      integer a,b,c,d,tile_dim,tile_size,e,f,i
      double precision bufc(LOCAL_BUFLEN), t2, t1
      integer ilo, ihi, ld
      character*(256) hostname
      integer j, td

      me = ga_nodeid()
      nproc = ga_nnodes()
      CALL ga_cluster_info(num_nodes, nodeid, collector_host, ppn)
      collector = me - mod(me,ppn)

      more_tasks = 1
      data_size = 0
      tile_size = 0
      tile_dim  = 0
      task_id = 0
      key = 0
      shmid = 0
      data_id = 0
      qlen = 0
      qid = 0


      do while (more_tasks.gt.0)

        call workq_get_max_qlen(nodeid, msqids, qlen, qid)
        if (qlen.eq.0) then
c         print *, "R:", me, "QLEN IS ZERO"
          call bench_workq(g_a, g_b, g_c,.false.,ga_cnt,msqids, 
     &                     td, num_collectors)
          return
        end if

        call workq_get_info(msqids, qid, data_id, shmid,  
     &    more_tasks, data_size, tile_dim, a, b, c, d, key, task_id, 
     &    me, ppn)

        IF (more_tasks.gt.0) THEN
          do i = 1, more_tasks
            bufc = 0
            call workq_dequeue_single(me, data_id, task_id, 
     &                                    tile_dim, i)
            t1 = ga_wtime()
            call workq_execute_task_single(bufc,
     &                tile_dim, 1.0d0, 2.0d0,'T','N',me)
            t2 = ga_wtime()
c           write(*, 20), "DGEMM(", me, "):", t2 - t1
c20         format (a,i2,a,2x,f10.6)


            tile_size = tile_dim*tile_dim
            ilo = task_id*tile_size + 1
            ihi = ilo + tile_size - 1
            ld = LOCAL_BUFLEN*nproc

            call ga_put(g_c, ilo, ihi, 1, 1, bufc, tile_dim)

          end do

        call workq_free_shm(task_id, data_size, shmid)
        END IF

      end do

      CALL bench_finalize(me, collector, nc, msqids)

      return
      end


      subroutine bench_finalize(me, collector, n_collectors, msqids)
      implicit none
#include "global.fh"
      integer me, collector, dummy, n_collectors
      integer msqids(7)

      call ga_sync()

      if (me.eq.collector) then
        call workq_destroy(msqids)
        call workq_destroy_sem()
      else
c       call workq_destroy_data(shmid)
      end if

      return
      end
      

      subroutine pexit(msg)
      implicit none
      integer nc
      character*(*) msg
      print *, msg
      call exit(-1)
      end
