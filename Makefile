.PHONY: install
install:
	@mkdir --parents $${HOME}/.local/bin \
	&& mkdir --parents $${HOME}/.config/systemd/user \
	&& cp ufd_exporter.sh $${HOME}/.local/bin/ \
	&& chmod +x $${HOME}/.local/bin/ufd_exporter.sh \
	&& cp --no-clobber ufd_exporter.conf $${HOME}/.config/ufd_exporter.conf \
	&& chmod 400 $${HOME}/.config/ufd_exporter.conf \
	&& cp ufd-exporter.timer $${HOME}/.config/systemd/user/ \
	&& cp ufd-exporter.service $${HOME}/.config/systemd/user/ \
	&& systemctl --user enable --now ufd-exporter.timer

.PHONY: uninstall
uninstall:
	@rm -f $${HOME}/.local/bin/ufd_exporter.sh \
	&& rm -f $${HOME}/.config/ufd_exporter.conf \
	&& systemctl --user disable --now ufd-exporter.timer \
	&& rm -f $${HOME}/.config/.config/systemd/user/ufd-exporter.timer \
	&& rm -f $${HOME}/.config/systemd/user/ufd-exporter.service
