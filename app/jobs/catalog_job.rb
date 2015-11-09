# CatalogJob is a job that synchronizes the contents of the database with the
# contents of the registries. This is done by using the Catalog API.
class CatalogJob < ActiveJob::Base
  # This method will be called on each tic of the cron. It basically goes
  # through all the registries and calls `update_registry!` for each of them.
  # Any error will be logged.
  def perform
    Registry.find_each do |registry|
      begin
        cat = registry.client.catalog

        # Update the registry in a transaction, since we don't want to leave
        # the DB in an unknown state because of an update failure.
        ActiveRecord::Base.transaction { update_registry!(cat) }
      rescue StandardError => e
        Rails.logger.warn "Exception: #{e.message}"
      end
    end
  end

  protected

  # This method updates the database of this application with the given
  # registry contents.
  def update_registry!(catalog)
    dangling_repos = Repository.all.pluck(:id)

    # In this loop we will create/update all the repos from the catalog.
    # Created/updated repos will be removed from the "repos" array.
    catalog.each do |r|
      cou   = Repository.create_or_update!(r)
      dangling_repos = dangling_repos.delete_if { |re| re == cou.id }
    end

    # At this point, the remaining items in the "repos" array are repos that
    # exist in the DB but not in the catalog. Remove all of them.
    Tag.where(repository_id: dangling_repos).find_each(&:delete_and_update!)
    Repository.where(id: dangling_repos).destroy_all
  end
end
