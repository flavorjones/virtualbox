require File.join(File.dirname(__FILE__), '..', 'test_helper')

class HardDriveTest < Test::Unit::TestCase
  setup do
    VirtualBox::Command.stubs(:execute)

    @find_raw = <<-raw
UUID:                 11dedd14-57a1-4bdb-adeb-dd1d67f066e1
Accessible:           yes
Description:
Logical size:         20480 MBytes
Current size on disk: 1218 MBytes
Type:                 normal (base)
Storage format:       VDI
In use by VMs:        FooVM (UUID: 696249ad-00b6-4087-b47f-9b82629efc31)
Location:             /Users/mitchellh/Library/VirtualBox/HardDisks/foo.vdi
raw
    @name = "foo"
    VirtualBox::Command.stubs(:vboxmanage).with("showhdinfo", @name).returns(@find_raw)
  end

  context "populating relationship" do
    setup do
      @xml = <<-xml
<MediaRegistry>
  <HardDisks>
    <HardDisk uuid="{9d2e4353-d1e9-466c-ac58-f2249264147b}" location="HardDisks/TestJeOS.vdi" format="VDI" type="Normal"/>
    <HardDisk uuid="{5f7ccd06-78ef-47e9-b2bc-515aedd2f288}" location="HardDisks/hobobase.vdi" format="VDI" type="Normal"/>
  </HardDisks>
</MediaRegistry>
xml
      @doc = Nokogiri::XML(@xml)
    end

    should "create an object for each hard disk entry" do
      result = VirtualBox::HardDrive.populate_relationship(nil, @doc)
      assert_equal 2, result.length
    end

    should "properly extract uuid, location, and format" do
      VirtualBox::Global.vboxconfig = "/foo/rawr.rb"
      result = VirtualBox::HardDrive.populate_relationship(nil, @doc)
      result = result[0]
      assert_equal "9d2e4353-d1e9-466c-ac58-f2249264147b", result.uuid
      assert_equal "VDI", result.format
      assert_equal "/foo/HardDisks/TestJeOS.vdi", result.location
    end
  end

  context "validations" do
    setup do
      @hd = VirtualBox::HardDrive.new
      @hd.size = 2000
    end

    should "be valid with a size and format" do
      assert @hd.valid?
    end

    should "be invalid if size is nil" do
      @hd.size = nil
      assert !@hd.valid?
    end

    should "clear validations when rechecking" do
      @hd.size = nil
      assert !@hd.valid?
      @hd.size = 700
      assert @hd.valid?
    end
  end

  context "destroying a hard drive" do
    setup do
      @hd = VirtualBox::HardDrive.find(@name)
    end

    should "call vboxmanage to destroy it" do
      VirtualBox::Command.expects(:vboxmanage).with("closemedium", "disk", @hd.uuid, "--delete")
      assert @hd.destroy
    end

    should "return false if destroy failed" do
      VirtualBox::Command.stubs(:vboxmanage).raises(VirtualBox::Exceptions::CommandFailedException)
      assert !@hd.destroy
    end

    should "raise an exception if failed and flag is set" do
      VirtualBox::Command.stubs(:vboxmanage).raises(VirtualBox::Exceptions::CommandFailedException)
      assert_raises(VirtualBox::Exceptions::CommandFailedException) {
        @hd.destroy(true)
      }
    end
  end

  context "cloning a hard drive" do
    setup do
      @hd = VirtualBox::HardDrive.find(@name)
      VirtualBox::Command.stubs(:vboxmanage).with("clonehd", @hd.uuid, "bar", "--format", "VDI", "--remember").returns(@find_raw)
    end

    should "call vboxmanage with the clone command" do
      VirtualBox::HardDrive.expects(:find).returns(nil)
      @hd.clone("bar")
    end

    should "return the newly cloned hard drive" do
      @new_hd = mock("hd")
      VirtualBox::HardDrive.expects(:find).returns(@new_hd)
      assert_equal @new_hd, @hd.clone("bar")
    end

    should "return false on failure" do
      VirtualBox::Command.stubs(:vboxmanage).raises(VirtualBox::Exceptions::CommandFailedException)
      assert @hd.clone("bar").nil?
    end

    should "raise an exception if raise_errors is true and failed" do
      VirtualBox::Command.stubs(:vboxmanage).raises(VirtualBox::Exceptions::CommandFailedException)
      assert_raises(VirtualBox::Exceptions::CommandFailedException) {
        @hd.clone("bar", "VDI", true)
      }
    end
  end

  context "creating a hard drive" do
    setup do
      @location = "foo.foo"
      @size = "758"
      @format = "VDI"

      @hd = VirtualBox::HardDrive.new
      @hd.location = @location
      @hd.size = @size

      @fake_hd = mock("hd")
      @fake_hd.stubs(:attributes).returns({
        :uuid => "foo"
      })

      VirtualBox::HardDrive.stubs(:find).returns(@fake_hd)
      VirtualBox::Command.stubs(:vboxmanage).returns("UUID: FOO")
    end

    should "call create on save" do
      @hd.expects(:create).once

      assert @hd.new_record?
      @hd.save
    end

    should "call not call create on existing records" do
      @hd.save
      assert !@hd.new_record?

      @hd.expects(:create).never
      @hd.save
    end

    should "call createhd" do
      VirtualBox::Command.expects(:vboxmanage).with("createhd", "--filename", @location, "--size", @size, "--format", @format, "--remember")
      @hd.save
    end

    should "replace attributes with those of the newly created hard drive" do
      @hd.save

      assert_equal "foo", @hd.uuid
    end

    should "return true if the command was a success" do
      assert @hd.save
    end

    should "return failure if the command failed" do
      VirtualBox::Command.stubs(:vboxmanage).raises(VirtualBox::Exceptions::CommandFailedException)
      assert !@hd.save
    end

    should "raise an exception if flag is set" do
      VirtualBox::Command.stubs(:vboxmanage).raises(VirtualBox::Exceptions::CommandFailedException)
      assert_raises(VirtualBox::Exceptions::CommandFailedException) {
        @hd.save(true)
      }
    end

    should "not run if invalid" do
      @hd.expects(:valid?).returns(false)
      VirtualBox::Command.expects(:vboxmanage).never
      assert !@hd.save
    end

    should "raise a ValidationFailedException if invalid and raise_errors is true" do
      @hd.expects(:valid?).returns(false)
      assert_raises(VirtualBox::Exceptions::ValidationFailedException) {
        @hd.save(true)
      }
    end
  end

  context "finding a single hard drive" do
    should "parse proper fields" do
      VirtualBox::Command.expects(:vboxmanage).with("showhdinfo", @name).returns(@find_raw)

      @expected = {
        :uuid => "11dedd14-57a1-4bdb-adeb-dd1d67f066e1",
        :accessible => "yes",
        :size => "20480",
        :location => "/Users/mitchellh/Library/VirtualBox/HardDisks/foo.vdi"
      }

      hd = VirtualBox::HardDrive.find(@name)
      assert hd.is_a?(VirtualBox::HardDrive)

      @expected.each do |k,v|
        assert_equal v, hd.send(k)
      end
    end

    should "return nil if finding a non-existent hard drive" do
      VirtualBox::Command.stubs(:vboxmanage).raises(VirtualBox::Exceptions::CommandFailedException)

      assert_nothing_raised do
        assert_nil VirtualBox::HardDrive.find(12)
      end
    end

    should "raise an exception if flag is set" do
      VirtualBox::Command.stubs(:vboxmanage).raises(VirtualBox::Exceptions::CommandFailedException)
      assert_raises(VirtualBox::Exceptions::CommandFailedException) {
        VirtualBox::HardDrive.find(12, true)
      }
    end
  end

  context "retrieving all hard drives" do
    should "return an array of HardDrive objects" do
      media = mock("media")
      media.expects(:hard_drives).returns("foo")
      global = mock("global")
      global.expects(:media).returns(media)
      VirtualBox::Global.expects(:global).returns(global)
      assert_equal "foo", VirtualBox::HardDrive.all
    end
  end
end