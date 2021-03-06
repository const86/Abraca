/**
 * Abraca, an XMMS2 client.
 * Copyright (C) 2008-2014 Abraca Team
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */

using GLib;

namespace Abraca {
	public class FilterModel : Gtk.ListStore, Gtk.TreeModel {
		/* Metadata resolve status */

		enum Status {
			UNRESOLVED,
			RESOLVING,
			RESOLVED
		}

		public enum Column {
			STATUS,
			ID
		}

		/* TODO: This should be a property, not just a member variable */
		public string[] dynamic_columns;

		/* Map medialib id to row */
		private Gee.Map<int,Gtk.TreeRowReference> pos_map = new Gee.HashMap<int,Gtk.TreeRowReference>();

		private Client client;
		private MetadataRequestor requestor;

		public FilterModel (Client c, MetadataResolver resolver, owned string[] props)
		{
			client = c;


			var types = new GLib.Type[2 + props.length];

			types[0] = typeof(int);
			types[1] = typeof(uint);

			for (int i = 2; i < types.length; i++) {
				types[i] = typeof(string);
			}

			set_column_types(types);

			dynamic_columns = (owned) props;

			requestor = resolver.register(on_resolver_complete);
			requestor.set_attributes(dynamic_columns);

			client.medialib_entry_changed.connect((client, res) => {
					on_medialib_info(res);
			});
		}


		/**
		 * Replaces the content of the filter list model with the
		 * result of a medialib query
		 */
		public bool replace_content (Xmms.Value val)
		{
			Gtk.TreeIter? iter, sibling = null;
			bool is_first = !get_iter_first(out iter);

			clear();

			pos_map.clear();


			unowned Xmms.ListIter list_iter;
			val.get_list_iter(out list_iter);

			for (list_iter.first(); list_iter.valid(); list_iter.next()) {
				Gtk.TreeRowReference row;
				Gtk.TreePath path;
				Xmms.Value entry;
				int id = 0;

				if (!(list_iter.entry(out entry) && entry.get_int(out id))) {
					continue;
				}

				if (is_first) {
					insert_after(out iter, null);
					is_first = !is_first;
				} else {
					insert_after(out iter, sibling);
				}

				set(iter, Column.ID, id, Column.STATUS, Status.UNRESOLVED);

				sibling = iter;

				path = get_path(iter);
				row = new Gtk.TreeRowReference(this, path);

				pos_map.set((int) id, row);
			}

			return true;
		}


		/**
		 * When GTK asks for the value of a column, check if the row
		 * has been resolved or not, otherwise resolve it.
		 */
		public void get_value (Gtk.TreeIter iter, int column, out GLib.Value val)
		{
			GLib.Value tmp1;

			base.get_value(iter, Column.STATUS, out tmp1);
			if (((Status)tmp1.get_int()) == Status.UNRESOLVED) {
				GLib.Value tmp2;

				base.get_value(iter, Column.ID, out tmp2);

				set(iter, Column.STATUS, Status.RESOLVING);

				requestor.resolve((int) tmp2.get_uint());
			}

			base.get_value(iter, column, out val);
		}


		private void on_resolver_complete(Xmms.Value value)
		{
			unowned Xmms.ListIter iter;
			Xmms.Value entry;

			value.get_list_iter(out iter);

			while (iter.entry(out entry)) {
				on_medialib_info(entry);
				iter.next();
			}
		}


		private bool on_medialib_info (Xmms.Value val)
		{
			Gtk.TreeRowReference row;
			Gtk.TreePath path;
			Gtk.TreeIter iter;
			int mid;

			val.dict_entry_get_int("id", out mid);

			row = pos_map.get(mid);
			if (row == null || !row.valid()) {
				return false;
			}

			path = row.get_path();

			if (get_iter(out iter, path)) {
				set(iter, Column.STATUS, Status.RESOLVED);

				int pos = 2;
				foreach (unowned string key in dynamic_columns) {
					string formatted = "";
					Transform.normalize_dict (val, key, out formatted);
					set(iter, pos++, formatted);
				}
			}

			return false;
		}
	}
}
