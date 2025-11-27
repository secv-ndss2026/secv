#include <linux/can.h>
#include <linux/can/raw.h>
#include <linux/ioctl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <net/if.h>
#include <unistd.h>
#include <time.h>

void die(char *s) {
  perror(s);
  exit(1);
}

int main() {
  struct ifreq ifr;
  struct sockaddr_can addr;
  struct can_frame frame;
  struct timespec start, end;
  int iterations = 1000;
  long long total_elapsed_time = 0;
  int s;
  char buf[] = "can_id_test";

  if ((s = socket(PF_CAN, SOCK_RAW, CAN_RAW)) == -1) {
    die("socket");
  }

  memset((char *)&ifr, 0, sizeof(ifr));
  strcpy(ifr.ifr_name, "can0");
  if (ioctl(s, SIOCGIFINDEX, &ifr) == -1) {
    die("ioctl");
  }

  memset(&addr, 0, sizeof(addr));
  addr.can_family = AF_CAN;
  addr.can_ifindex = ifr.ifr_ifindex;

  if (bind(s, (struct sockaddr *)&addr, sizeof(addr)) == -1) {
    die("bind");
  }

  frame.can_id = 0x123;
  frame.can_dlc = 8;
  frame.data[0] = 0x11;
  frame.data[1] = 0x22;
  frame.data[2] = 0x33;
  frame.data[3] = 0x44;
  frame.data[4] = 0x55;
  frame.data[5] = 0x66;
  frame.data[6] = 0x77;
  frame.data[7] = 0x88;

  for (int i = 0; i < iterations; ++i) {
    clock_gettime(CLOCK_MONOTONIC, &start);

    if (sendto(s, &frame, sizeof(struct can_frame), 0, (struct sockaddr *)&addr,
               sizeof(addr)) == -1) {
      die("sendto()");
    }

    clock_gettime(CLOCK_MONOTONIC, &end);

    long long elapsed_ns = (end.tv_sec - start.tv_sec) * 1000000000LL +
                           (end.tv_nsec - start.tv_nsec);
    printf("Elapsed time: %lld ns\n", elapsed_ns);
    total_elapsed_time += elapsed_ns;
  }

  close(s);

  printf("Number of iterations: %d\n", iterations);
  printf("Total elapsed time: %lld ns\n", total_elapsed_time);
  printf("Average time per sendto() call: %.2f ns\n",
         (double)total_elapsed_time / iterations);

  return 0;
}
