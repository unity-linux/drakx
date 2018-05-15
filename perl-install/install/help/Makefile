help:
	@if [ ! -d doc ]; then \
		echo "Checking out doc stuff now ..."; \
		cvs -d :ext:svn.mageia.org:/cauldron co doc/manualB/{entities,manuals,modules}; \
	else \
		echo "Updating doc stuff now ..."; \
		cd doc ; cvs update manualB/{entities,manuals,modules}; \
	fi
	./help_xml2pm.pl
