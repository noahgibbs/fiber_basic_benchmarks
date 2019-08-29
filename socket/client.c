/* Most code taken from http://beej.us/guide/bgnet/html/multi/clientserver.html */

// To compile: gcc client.c -Wall -o ./client
// To run: ./client localhost

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <netdb.h>
#include <sys/types.h>
#include <netinet/in.h>
#include <sys/socket.h>

#include <arpa/inet.h>

#define PORT "9090"

// get sockaddr, IPv4 or IPv6:
void *get_in_addr(struct sockaddr *sa)
{
  if (sa->sa_family == AF_INET) {
    return &(((struct sockaddr_in*)sa)->sin_addr);
  }

  return &(((struct sockaddr_in6*)sa)->sin6_addr);
}

// Should actually never be more than "OK" as a response
#define MAXDATASIZE 10
static char buf[MAXDATASIZE];  // Should never be more than "OK"

int client(struct addrinfo *servinfo)
{
  int numbytes, sockfd;
  struct addrinfo *p;
  //char s[INET6_ADDRSTRLEN];

  // loop through all the results and connect to the first we can
  for(p = servinfo; p != NULL; p = p->ai_next) {
    if ((sockfd = socket(p->ai_family, p->ai_socktype,
                         p->ai_protocol)) == -1) {
      perror("client: socket");
      continue;
    }

    if (connect(sockfd, p->ai_addr, p->ai_addrlen) == -1) {
      close(sockfd);
      perror("client: connect");
      continue;
    }

    break;
  }

  if (p == NULL) {
    fprintf(stderr, "client: failed to connect\n");
    return -1;
  }

  //inet_ntop(p->ai_family, get_in_addr((struct sockaddr *)p->ai_addr),
  //          s, sizeof s);
  //printf("client: connecting to %s\n", s);

  if ((numbytes = recv(sockfd, buf, MAXDATASIZE-1, 0)) == -1) {
    perror("recv");
    exit(1);
  }

  buf[numbytes] = '\0';
  close(sockfd);

  if(buf[0] == 'O' && buf[1] == 'K' && buf[2] == '\0') {
    return 0;
  } else {
    fprintf(stderr, "Socket read expected 'OK' but instead got '%s'\n", buf);
    return -3;
  }
}

int main(int argc, char **argv)
{
  struct addrinfo hints, *servinfo;
  int rv;
  int i;
  int attempts;

  if (argc != 3) {
    fprintf(stderr,"usage: client hostname conn_attempts\n  Example: client localhost 10000\n");
    exit(1);
  }

  attempts = atoi(argv[2]);
  if(attempts < 1) {
    fprintf(stderr, "Instead of a correct number of attempts, you gave: %s\n", argv[2]);
    return 1;
  }

  memset(&hints, 0, sizeof hints);
  hints.ai_family = AF_UNSPEC;
  hints.ai_socktype = SOCK_STREAM;

  if ((rv = getaddrinfo(argv[1], PORT, &hints, &servinfo)) != 0) {
    fprintf(stderr, "getaddrinfo: %s\n", gai_strerror(rv));
    return 1;
  }

  for(i = 0; i < attempts; i++) {
    rv = client(servinfo);
    if(rv != 0) break;
  }
  printf("Client call returned %d on call no. %d\n", rv, i);

  freeaddrinfo(servinfo); // all done with this structure

}
