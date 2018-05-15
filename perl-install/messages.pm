package messages;

use diagnostics;
use strict;

use common;

sub main_license() {
    join("\n\n\n",
         #-PO: Only write something if needed:
         N("_: You can warn about unofficial translation here"),
         main_license_raw()
     );
}

sub main_license_raw() {
    join("\n\n\n",
N("Introduction"),

N("The operating system and the different components available in the Mageia distribution 
shall be called the \"Software Products\" hereafter. The Software Products include, but are not 
restricted to, the set of programs, methods, rules and documentation related to the operating 
system and the different components of the Mageia distribution, and any applications 
distributed with these products provided by Mageia's licensors or suppliers."),


N("1. License Agreement"),

N("Please read this document carefully. This document is a license agreement between you and  
Mageia which applies to the Software Products.
By installing, duplicating or using any of the Software Products in any manner, you explicitly 
accept and fully agree to conform to the terms and conditions of this License. 
If you disagree with any portion of the License, you are not allowed to install, duplicate or use 
the Software Products. 
Any attempt to install, duplicate or use the Software Products in a manner which does not comply 
with the terms and conditions of this License is void and will terminate your rights under this 
License. Upon termination of the License,  you must immediately destroy all copies of the 
Software Products."),


N("2. Limited Warranty"),

#-PO: keep the double empty lines between sections, this is formatted a la LaTeX
N("The Software Products and attached documentation are provided \"as is\", with no warranty, to the 
extent permitted by law.
Neither Mageia nor its licensors or suppliers will, in any circumstances and to the extent 
permitted by law, be liable for any special, incidental, direct or indirect damages whatsoever 
(including without limitation damages for loss of business, interruption of business, financial 
loss, legal fees and penalties resulting from a court judgment, or any other consequential loss) 
arising out of  the use or inability to use the Software Products, even if Mageia or its 
licensors or suppliers have been advised of the possibility or occurrence of such damages.

LIMITED LIABILITY LINKED TO POSSESSING OR USING PROHIBITED SOFTWARE IN SOME COUNTRIES

To the extent permitted by law, neither Mageia nor its licensors, suppliers or
distributors will, in any circumstances, be liable for any special, incidental, direct or indirect 
damages whatsoever (including without limitation damages for loss of business, interruption of 
business, financial loss, legal fees and penalties resulting from a court judgment, or any 
other consequential loss) arising out of the possession and use of software components or 
arising out of  downloading software components from one of Mageia sites which are 
prohibited or restricted in some countries by local laws.
This limited liability applies to, but is not restricted to, the strong cryptography components 
included in the Software Products.
However, because some jurisdictions do not allow the exclusion or limitation of liability for 
consequential or incidental damages, the above limitation may not apply to you."),


N("3. The GPL License and Related Licenses"),

N("The Software Products consist of components created by different persons or entities.
Most of these licenses allow you to use, duplicate, adapt or redistribute the components which 
they cover. Please read carefully the terms and conditions of the license agreement for each component 
before using any component. Any question on a component license should be addressed to the component 
licensor or supplier and not to Mageia.
The programs developed by Mageia are governed by the GPL License. Documentation written 
by Mageia is governed by \"%s\" License.", "CC-By-SA"),


N("4. Intellectual Property Rights"),

N("All rights to the components of the Software Products belong to their respective authors and are 
protected by intellectual property and copyright laws applicable to software programs.
Mageia and its suppliers and licensors reserves their rights to modify or adapt the Software 
Products, as a whole or in parts, by all means and for all purposes.
\"Mageia\" and associated logos are trademarks of %s", "Mageia.Org"),


N("5. Governing Laws"),

N("If any portion of this agreement is held void, illegal or inapplicable by a court judgment, this 
portion is excluded from this contract. You remain bound by the other applicable sections of the 
agreement.
The terms and conditions of this License are governed by the Laws of France.
All disputes on the terms of this license will preferably be settled out of court. As a last 
resort, the dispute will be referred to the appropriate Courts of Law of Paris - France.
For any question on this document, please contact Mageia."),
         warning_about_patents()
    );
}

sub warning_about_patents() {
N("Warning: Free Software may not necessarily be patent free, and some Free
Software included may be covered by patents in your country. For example, the
MP3 decoders included may require a license for further usage (see
http://www.mp3licensing.com for more details). If you are unsure if a patent
may be applicable to you, check your local laws.");
}

sub install_completed() {
	join("\n\n\n", 
	     N("Congratulations, installation is complete.
Remove the boot media and press Enter to reboot."),
	     N("For information on fixes which are available for this release of Mageia,
consult the Errata available from:\n%s", 'http://www.mageia.org/'),
	     N("After rebooting and logging into Mageia, you will see the MageiaWelcome screen.
It is full of very useful information and links.")
	    );
}

1;
