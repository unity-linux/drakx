/*
 * Guillaume Cottenceau (gc)
 *
 * Copyright 2000 Mandriva
 *
 * This software may be freely redistributed under the terms of the GNU
 * public license.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 */

/*
 * Portions from Erik Troan (ewt@redhat.com)
 *
 * Copyright 1996 Red Hat Software 
 *
 */

#include <stdlib.h>

#include <unistd.h>
#include <string.h>
#include <stdio.h>
#include <netdb.h>
#include <sys/socket.h>
#include <resolv.h>

#include "network.h"
#include "log.h"

#include "dns.h"

int mygethostbyname(char * name, struct in_addr * addr)
{
	struct addrinfo hints, *res, *p;
	int status;
	char ipstr[INET6_ADDRSTRLEN];

	memset(&hints, 0, sizeof hints);
	hints.ai_family = AF_INET; //AF_UNSPEC for both IPv4 & IPv6
	hints.ai_socktype = SOCK_STREAM;

	/* prevent from timeouts */
	if (_res.nscount == 0) 
		return -1;

	if ((status = getaddrinfo(name, NULL, &hints, &res)) != 0) {
          log_message("getaddrinfo: %s\n", gai_strerror(status));
          return -1;
	}

	for (p = res;p != NULL; p = p->ai_next) {
          void *tmp_addr;

          struct sockaddr_in *ipv = (struct sockaddr_in *)p->ai_addr;
          tmp_addr = &(ipv->sin_addr);

          /* convert the IP to a string: */
          inet_ntop(p->ai_family, addr, ipstr, sizeof ipstr);

	  memcpy(addr, tmp_addr, sizeof(*addr));
	  log_message("is-at: %s\n", inet_ntoa(*addr));
	}

	freeaddrinfo(res); // free the linked list
	return 0;
}

char * mygethostbyaddr(char * ipnum)
{
	struct sockaddr_in sa;
	char hbuf[NI_MAXHOST];

        /* prevent from timeouts */
        if (_res.nscount == 0) 
                return NULL;
  
	memset(&sa, 0, sizeof sa);
	sa.sin_family = AF_INET;

	if (inet_pton(AF_INET, ipnum, &sa.sin_addr) != 1)
          return NULL;

	if (getnameinfo((struct sockaddr*)&sa, sizeof(sa), hbuf, sizeof(hbuf), NULL, 0, 0 |NI_NAMEREQD) == 0) //NI_NUMERICHOST  NI_NAMEREQD
          return strdup(hbuf);
	else return NULL;
}
