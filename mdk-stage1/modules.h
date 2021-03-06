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

#ifndef _MODULES_H_
#define _MODULES_H_

#include "stage1.h"
#include "probing.h"

enum insmod_return { INSMOD_OK, INSMOD_FAILED, INSMOD_FAILED_FILE_NOT_FOUND };

void init_modules_insmoding(void);
void init_firmware_loader(void);
int insmod_local_file(char * path, char * options);
enum insmod_return my_modprobe(const char * mod_name, enum driver_type type, char * options);
enum return_type ask_insmod(enum driver_type);
int module_already_present(const char * name);

struct module_descr_elem {
    char * modname;
    char * description;
};

extern int disable_modules;

#endif
